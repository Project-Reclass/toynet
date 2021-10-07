from marshmallow import Schema, fields, ValidationError
from flask_restful import abort
from flask_apispec import marshal_with, MethodResource, use_kwargs
from flasksrc.db import get_db

from flasksrc.emulator.commandParser import parseModificationCommand
from flasksrc.toynet_manager import ToynetManager

import requests
import time
import os
import sys
from xml.etree import ElementTree as ET

MINI_FLASK_PORT = os.environ['MINI_FLASK_PORT']
COMPOSE_NETWORK = 'bridge'
if 'COMPOSE_NETWORK' in os.environ and os.environ['COMPOSE_NETWORK'] != '':
    COMPOSE_NETWORK = os.environ['COMPOSE_NETWORK']


# Schema definitions
class ToyNetSessionPostReq(Schema):
    toynet_topo_id = fields.Int()
    toynet_user_id = fields.Str()


class ToyNetSessionPostResp(Schema):
    toynet_session_id = fields.Int()
    running = fields.Bool()


class ToyNetSessionByIdGetResp(Schema):
    topo_id = fields.Int()
    user_id = fields.Str()
    topology = fields.Str()
    running = fields.Bool()


class ToyNetSessionByIdPutReq(Schema):
    command = fields.Str()
    ip = fields.Str()


class ToyNetSessionByIdPostReq(Schema):
    toynet_command = fields.Str()


class ToyNetSessionByIdPostResp(Schema):
    output = fields.Str()


class ToyNetSessionByIdCreateHostPutReq(Schema):
    name = fields.Str()
    ip = fields.Str()
    def_gateway = fields.Str()


class ToyNetSessionByIdCreateHostPutResp(Schema):
    pass


class ToyNetSessionByIdCreateSwitchPutReq(Schema):
    name = fields.Str()


class ToyNetSessionByIdCreateSwitchPutResp(Schema):
    pass


class ToyNetSessionByIdDeleteDevicePutReq(Schema):
    name = fields.Str()


class ToyNetSessionByIdDeleteDevicePutResp(Schema):
    pass


# Hack to maintain docker container tracking state across requests, should not
# be an issue at this scale, contains a ToynetManager instance
# This class contains:
#   manager: ToynetManager object
#   containers: dict[session_id - int]: name of Docker Container object - str
class State():
    # Throws an exception when the network does not exist
    manager = ToynetManager(COMPOSE_NETWORK)

    dev_status = os.environ['FLASK_ENV'] == 'development'
    if not manager.import_image(dev_status, os.environ['TOYNET_IMAGE_TAG']):
        print(f'Failed to import image: {os.environ["TOYNET_IMAGE_TAG"]}', file=sys.stderr)
        sys.exit(1)
    containers = dict()

    @staticmethod
    def getDevStatus():
        return State.dev_status

    @staticmethod
    def getManager():
        return State.manager

    @staticmethod
    def getContainer(session):
        if session in State.containers:
            return State.manager.running_containers[State.containers[session]]
        else:
            return None

    @staticmethod
    def setContainer(session, container):
        State.containers[session] = container

    @staticmethod
    def delContainer(session):
        res = False
        if session in State.containers:
            res = State.manager.kill_container(State.containers[session])
            if res:
                del State.containers[session]
        return res


# Post data to a miniflask resource for the provided container
def miniflaskPost(container, resource, args=None):
    ip = container.attrs['NetworkSettings']['IPAddress']
    # Stored under the network object if on a non-default network
    if COMPOSE_NETWORK != 'bridge':
        ip = container.attrs['NetworkSettings']['Networks'][COMPOSE_NETWORK]['IPAddress']
    res = requests.post(f'http://{ip}:{MINI_FLASK_PORT}{resource}', json=args)
    return res


# Get data from a miniflask resource for the provided container
def miniflaskGet(container, resource, args=None):
    ip = container.attrs['NetworkSettings']['IPAddress']
    # Stored under the network object if on a non-default network
    if COMPOSE_NETWORK != 'bridge':
        ip = container.attrs['NetworkSettings']['Networks'][COMPOSE_NETWORK]['IPAddress']
    res = requests.get(f'http://{ip}:{MINI_FLASK_PORT}{resource}', json=args)
    return res


# Wait for a miniflask container to finish initializing and serve up endpoints
def waitForMiniflask(container, toynet_session_id):
    counter = 500
    container.reload()

    # Wait for the container to start
    while not container.attrs['State']['Running'] and counter > 0:
        time.sleep(10)
        counter -= 1  # "Counter" intuitive?
        container.reload()

    # Container did not spin up
    if counter == 0:
        State.delContainer(toynet_session_id)
        return False
    else:
        # Wait for miniflask to serve endpoints, will not timeout
        res_code = 404
        while res_code != 200:
            try:
                res_code = miniflaskGet(container, '/').status_code
            except requests.exceptions.ConnectionError:
                time.sleep(10)

    return True


# Update the topology in Mininet, aborts REST call on failure
def sendTopoToMininet(toynet_session_id, new_topology):
    container = State.getContainer(toynet_session_id)
    if container is not None:
        running = waitForMiniflask(container, toynet_session_id)

        if running:
            args = {'topology': new_topology}
            res = miniflaskPost(container, '/api/topo', args=args)

            # Propagate the error if there is one
            if res.status_code != 200:
                abort(res.status_code, message=res.json()['message'])
    else:
        abort(500, message='Container for session does not exist, cannot update topology')


# Gets the specified session's topology from the specified DB, aborts REST call
# on failure
def getTopologyFromDb(toynet_session_id):
    db = get_db()

    try:
        rows = db.execute(
            'SELECT topo_id, topology, user_id'
            ' FROM toynet_sessions'
            ' WHERE session_id = (?)',
            (str(toynet_session_id),)
        ).fetchall()
    except Exception:
        abort(500, message='Query for session_id failed: {}'.format(toynet_session_id))

    if not len(rows):
        abort(400, message='session_id {} does not exist'.format(toynet_session_id))

    return rows[0]


# Updates the specified session with the specified topology in the DB, aborts
# REST call on failure
def updateTopoInDb(toynet_session_id, new_topo):
    db = get_db()

    try:
        db.execute(
            'UPDATE toynet_sessions'
            ' SET topology = (?)'
            ' WHERE session_id = (?)',
            (new_topo, str(toynet_session_id),)
        )
        db.commit()
    except Exception:
        abort(500, message='Query for toynet_session_id failed: {}'.format(toynet_session_id))


class ToyNetSession(MethodResource):
    @use_kwargs(ToyNetSessionPostReq)
    @marshal_with(ToyNetSessionPostResp)
    def post(self, **kwargs):
        try:
            req = ToyNetSessionPostReq().load(kwargs)
        except ValidationError as e:
            abort(400, message=f'malformed request: {e.messages}')

        toynet_topo_id = req['toynet_topo_id']
        toynet_user_id = req['toynet_user_id']

        db = get_db()

        try:
            topo_rows = db.execute(
                'SELECT topology'
                ' FROM toynet_topos'
                ' WHERE topo_id = (?)',
                (str(toynet_topo_id),)
            ).fetchall()
        except Exception:
            abort(500, message='topo_id query failed: {}'.format(toynet_topo_id))

        if not len(topo_rows):
            abort(400, message='topo_id is invalid: {}'.format(toynet_topo_id))

        try:
            user_rows = db.execute(
                'SELECT username'
                ' FROM users'
                ' WHERE username = (?)',
                (str(toynet_user_id),)
            ).fetchall()
        except Exception:
            abort(500, message='user_id query failed: {}'.format(toynet_user_id))

        if not len(user_rows):
            abort(400, message='user_id is invalid: {}'.format(toynet_user_id))

        try:
            cur = db.cursor()
            cur.execute(
                'INSERT INTO toynet_sessions(topo_id, topology, user_id)'
                ' VALUES(?,?,?)',
                (str(toynet_topo_id), topo_rows[0]['topology'], toynet_user_id,)
            )
            db.commit()
            session_id = cur.lastrowid
        except Exception:
            abort(500, message='Failed to create new session')

        manager = State.getManager()
        running = True

        # Create corresponding miniflask container
        if manager.check_cpu_availability and manager.check_memory_availability:
            name = manager.run_mininet_container(dev=State.getDevStatus(), net=COMPOSE_NETWORK)
            State.setContainer(session_id, name)

            container = State.getContainer(session_id)
            running = waitForMiniflask(container, session_id)

            if running:
                args = {'topology': topo_rows[0]['topology']}
                res = miniflaskPost(container, '/api/topo', args=args)

                if res.status_code != 200:
                    running = False

        # Insufficient resources
        else:
            running = False

        return {
            'toynet_session_id': session_id,
            'running': running,
            }, 201


class ToyNetSessionById(MethodResource):
    @marshal_with(ToyNetSessionByIdGetResp)
    def get(self, toynet_session_id):
        sessionInfo = getTopologyFromDb(toynet_session_id)
        container = State.getContainer(toynet_session_id)
        manager = State.getManager()
        running = True

        # Spin up a miniflask container if one does not exist
        if container is None:
            running = False
            if manager.check_cpu_availability and manager.check_memory_availability:
                name = manager.run_mininet_container(dev=State.getDevStatus(), net=COMPOSE_NETWORK)
                State.setContainer(toynet_session_id, name)
                container = State.getContainer(toynet_session_id)

                running = waitForMiniflask(container, toynet_session_id)

                if running:
                    args = {'topology': sessionInfo['topology']}
                    res = miniflaskPost(container, '/api/topo', args=args)

                    if res.status_code == 200:
                        running = True

        return {
            'topo_id': sessionInfo['topo_id'],
            'topology': sessionInfo['topology'],
            'user_id': sessionInfo['user_id'],
            'running': running,
        }, 200

    @use_kwargs(ToyNetSessionByIdPutReq)
    def put(self, toynet_session_id, **kwargs):
        try:
            req = ToyNetSessionByIdPutReq().load(kwargs)
        except ValidationError as e:
            abort(400, message=f'malformed request: {e.messages}')

        ip = None
        if 'command' not in req:
            abort(400, message='missing [command] argument')
        if 'ip' in req:
            ip = req['ip']

        sessionInfo = getTopologyFromDb(toynet_session_id)
        xmlTopology = sessionInfo['topology']
        new_topo = parseModificationCommand(req['command'], xmlTopology, ip=ip)

        sendTopoToMininet(toynet_session_id, new_topo)
        updateTopoInDb(toynet_session_id, new_topo)

        return {
            }, 200

    @use_kwargs(ToyNetSessionByIdPostReq)
    @marshal_with(ToyNetSessionByIdPostResp)
    def post(self, toynet_session_id, **kwargs):
        try:
            req = ToyNetSessionByIdPostReq().load(kwargs)
        except ValidationError as e:
            abort(400, message='Invalid request: {}'.format(e))

        container = State.getContainer(toynet_session_id)
        if container is None:
            abort(500, message='Invalid Session ID. No corresponding toynet container.')

        # Separate validation from Marshmallow
        if 'toynet_command' not in req:
            abort(400, message='toynet_command not specified')

        args = {'command': req['toynet_command']}
        res = miniflaskPost(container, '/api/command', args=args)

        if res.status_code != 200:
            abort(res.status_code, message=res.json()['message'])

        return {
            'output': res.json()['output']
        }, 200


class ToyNetSessionByIdTerminate(MethodResource):
    def post(self, toynet_session_id):
        container = State.getContainer(toynet_session_id)
        if container is None:
            abort(500, message='Failed to terminate')

        # In the future we may want to handle failed MiniFlask terminate
        # requests differently. For now we are not preserving state, so we
        # terminate the container within State's ToynetManager
        args = {'terminate': True}
#        res = miniflaskPost(container, '/api/terminate', args=args)
        miniflaskPost(container, '/api/terminate', args=args)

#        if res.status_code != 200 or not res.json()['terminated']:
#            abort(500, message='Failed to terminate')

        res = State.delContainer(toynet_session_id)

        if res is None:
            abort(500, message='Container does not exist')
        elif not res:
            abort(500, message='Failed to terminate')
        else:
            return {
                }, 200


class ToyNetSessionByIdCreateHost(MethodResource):
    @use_kwargs(ToyNetSessionByIdCreateHostPutReq)
    @marshal_with(ToyNetSessionByIdCreateHostPutResp)
    def put(self, toynet_session_id, **kwargs):
        try:
            req = ToyNetSessionByIdCreateHostPutReq().load(kwargs)
        except ValidationError as e:
            abort(400, message='Invalid request: {}'.format(e))

        # Separate validation from Marshmallow
        if 'ip' not in req:
            abort(400, message='Missing ip from req')
        elif 'name' not in req:
            abort(400, message='Missing name from req')
        elif 'def_gateway' not in req:
            abort(400, message='Missing def_gateway from req')

        orig_topology = getTopologyFromDb(toynet_session_id)['topology']
        root = ET.fromstring(orig_topology)

        # Create XML elements for topology
        host = ET.Element('host')
        host.attrib['name'] = req['name']
        host.attrib['ip'] = req['ip']

        defaultRouter = ET.Element('defaultRouter')
        defaultRouterName = ET.Element('name')
        defaultRouterIntf = ET.Element('intf')

        # Get the router name and interface from the specified IP
        for router in root.find('routerList'):
            for intf, router_ip in enumerate(router.findall('intf')):
                if req['def_gateway'] == router_ip.text.split('/')[0]:
                    defaultRouterName.text = router.get('name')
                    defaultRouterIntf.text = str(intf)
                    break
            else:
                continue
            break  # Used with the above 'else' to break out of both loops
        else:
            abort(400, message=f'No router with IP: {req["def_gateway"]}')

        defaultRouter.append(defaultRouterName)
        defaultRouter.append(defaultRouterIntf)
        host.append(defaultRouter)

        # Update the topology
        root.find('hostList').append(host)
        new_topology = ET.tostring(root).decode('utf-8')

        # Send to mininet and update DB, these functions abort the REST call on
        # failure
        sendTopoToMininet(toynet_session_id, new_topology)
        updateTopoInDb(toynet_session_id, new_topology)

        return {
            }, 200


class ToyNetSessionByIdCreateSwitch(MethodResource):
    @use_kwargs(ToyNetSessionByIdCreateSwitchPutReq)
    @marshal_with(ToyNetSessionByIdCreateSwitchPutResp)
    def put(self, toynet_session_id, **kwargs):
        try:
            req = ToyNetSessionByIdCreateSwitchPutReq().load(kwargs)
        except ValidationError as e:
            abort(400, message='Invalid request: {}'.format(e))

        # Separate validation from Marshmallow
        if 'name' not in req:
            abort(400, message='Missing name from req')

        orig_topology = getTopologyFromDb(toynet_session_id)['topology']
        root = ET.fromstring(orig_topology)

        # Create XML elements for topology
        switch = ET.Element('switch')
        switch.attrib['name'] = req['name']

        # Update the topology
        root.find('switchList').append(switch)
        new_topology = ET.tostring(root).decode('utf-8')

        # Send to mininet and update DB, these functions abort the REST call on
        # failure
        sendTopoToMininet(toynet_session_id, new_topology)
        updateTopoInDb(toynet_session_id, new_topology)

        return {
            }, 200


class ToyNetSessionByIdDeleteDevice(MethodResource):
    def deleteDevice(self, toynet_session_id, device_type, name, orig_topology):
        root = ET.fromstring(orig_topology)

        # Verify that there is no link to the device
        for link in root.find('linkList').iter('dvc'):
            if name == link.attrib['name']:
                abort(400, message=f'Device {name} is connected to another device')

        # Update the topology
        for device in root.find(f'{device_type}List'):
            if device.attrib['name'] == name:
                root.find(f'{device_type}List').remove(device)
                break

        new_topology = ET.tostring(root).decode('utf-8')

        # Send to mininet and update DB, these functions abort the REST call on
        # failure
        sendTopoToMininet(toynet_session_id, new_topology)
        updateTopoInDb(toynet_session_id, new_topology)

    @use_kwargs(ToyNetSessionByIdDeleteDevicePutReq)
    @marshal_with(ToyNetSessionByIdDeleteDevicePutResp)
    def put(self, toynet_session_id, device_type, **kwargs):
        try:
            req = ToyNetSessionByIdDeleteDevicePutReq().load(kwargs)
        except ValidationError as e:
            abort(400, message='Invalid request: {}'.format(e))

        if 'name' not in req:
            abort(400, message='No device name specified')

        if device_type in ['host', 'switch', 'router']:
            topology = getTopologyFromDb(toynet_session_id)['topology']
            self.deleteDevice(toynet_session_id, device_type, req['name'], topology)
        else:
            abort(400, message=f'Invalid device type: {device_type}')

        return {
            }, 200
