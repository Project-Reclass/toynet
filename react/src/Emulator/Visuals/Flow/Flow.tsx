/*
Copyright (C) 1992-2021 Free Software Foundation, Inc.

This file is part of ToyNet React.

ToyNet React is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

ToyNet React is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License
along with ToyNet React; see the file LICENSE.  If not see
<http://www.gnu.org/licenses/>.

*/

import { useCallback, useEffect, useMemo, useState } from 'react';
import styled from '@emotion/styled';
import localforage from 'localforage';
import { useBoolean } from '@chakra-ui/react';
import ReactFlow, {
  Controls,
  Background,
  Elements,
  updateEdge,
  OnLoadParams,
  FlowExportObject,
  useZoomPanHelper,
  Edge,
  Connection,
} from 'react-flow-renderer';

import { devError } from 'src/common/utils';
import { DeviceInterface } from 'src/common/types';
import { SessionId } from 'src/common/api/topology/types';
import { TopologyActions } from 'src/Emulator/useTopology';
import { useDialogue, useEmulator } from 'src/common/providers/EmulatorProvider';
import { useCreateDeviceLink } from 'src/common/api/topology';
import RestartModal from 'src/Emulator/Instructions/RestartModal';

import ClickableNode from './ClickableNode';
import isInValidLink from './isInValidLink';
import {
  createElements,
  getLayoutedElements,
  mergeElementLayouts,
} from './utils';

import './overrides.css';
import CustomControls from './CustomControls';

export interface Props {
  sessionId: SessionId;
  hosts: DeviceInterface[],
  routers: DeviceInterface[],
  switches: DeviceInterface[],

  isTesting?: boolean,
}

localforage.config({
  name: 'emulator-flow',
  storeName: 'flow',
});

const DEFAULT_BG_GAP = 16;
const FLOW_STORE_KEY = 'flow-ui';

const RightAlignedControls = styled(Controls)`
  right: 10px;
  left: unset !important;
`;

/**
 * Determines the number of the newly added device
 */
 export const getNextNumber = (s: string) => Number(s.slice(1)) + 1;

/**
 * Determines the name of the newly added device
 */
 export const getNextDeviceName = (
   device: Array<{name: string}>,
   deviceLetter: string,
) => {
  if (device.length < 1) {
    return `${deviceLetter}1`;
  } else {
    const lastDeviceName = device[device.length - 1].name;
    return `${deviceLetter}${getNextNumber(lastDeviceName)}`;
  }
};

const nodeTypes = {
  default: ClickableNode,
};

const Flow = ({
  sessionId,
  switches,
  routers,
  hosts,
  isTesting = false,
}: Props) => {
  const [isRestartModalOpen, setRestartModal] = useBoolean(false);
  const [rfInstance, setRfInstance] = useState<OnLoadParams | null>(null);

  const [elements, setElements] = useState<Elements>([]);
  const { appendDialogue, updateDialogueMessage } = useDialogue();
  const { dispatch } = useEmulator();
  const { isLoading, mutateAsync: createLink } = useCreateDeviceLink(sessionId);

  const { transform, fitView } = useZoomPanHelper();

  /**
   * We need to use the `sessionId` here since we do not want
   * lto use an old session's layout when the user creates a new toynet session.
   */
  const flowSessionKey = useMemo(() =>
    `${FLOW_STORE_KEY}-${sessionId}`, [sessionId]);

  const handleRestore = useCallback((newElements: Elements) => {
    // this is needed because when the component is first rendered it the
    // devices will be empty. This causes an race issue when getting the flow
    // elements from IndexDB. The empty array could resolve after the call with
    // the actual elements to render.
    if (newElements.length === 0)
      return;

    const restore = async () => {
      const flow = await localforage.getItem<FlowExportObject>(flowSessionKey);
      const [x = 1, y = 1] = flow?.position || [];
      setElements(mergeElementLayouts(newElements, flow?.elements || []));
      if (newElements.length === flow?.elements.length) {
        transform({ x, y, zoom: flow?.zoom || 1 });
      }
    };

    restore();
  }, [flowSessionKey, transform]);

  const handleSave = useCallback(() => {
    if (rfInstance) {
      const flow = rfInstance.toObject();
      localforage.setItem(flowSessionKey, flow);
    }
  }, [flowSessionKey, rfInstance]);

  useEffect(() => {
    const els = createElements([...routers, ...switches, ...hosts]);
    handleRestore(getLayoutedElements(els, 'LR', isTesting));
  }, [hosts, routers, switches, isTesting, handleRestore]);

  const onConnect = async (params: Edge | Connection) => {
    const { source, target } = params;

    const allDevices = [...routers, ...hosts, ...switches];
    const sourceDevice = allDevices.find(device => device.name === source);
    const targetDevice = allDevices.find(device => device.name === target);

    const isInValidMessage = isInValidLink(sourceDevice, targetDevice);
    if (isInValidMessage) {
      appendDialogue(isInValidMessage, 'tomato');
      return;
    }

    dispatch({ type: TopologyActions.ADD_CONNECTION, payload: { from: source || '', to: target || '' }});
    const messageId = appendDialogue(
      `Attempting to create link ${source} to ${target}...`, 'grey');
    try {
      await createLink({ dev_1: source || '', dev_2: target || ''});
      updateDialogueMessage(messageId, {
        message: `Created link ${source} to ${target}`,
        color: 'White',
      });
    } catch (error) {
      devError(error);
      updateDialogueMessage(messageId, {
        message: `Unable to create link ${source} to ${target}`,
        color: 'tomato',
      });

      // Because we eagerly make the connection, if there was an error, we need to
      // delete the connection.
      dispatch({ type: TopologyActions.DELETE_CONNECTION, payload: { from: source || '', to: target || '' }});
    }
  };

  const handleAutoFormat = () => {
    const els = createElements([...routers, ...switches, ...hosts]);
    setElements(getLayoutedElements(els, 'LR', isTesting));

    // We add the fitView to the callback queue so that this function is called
    // after the the layout is already updated before we fit the view.
    setTimeout(() => fitView({ padding: 1 }), 0);
  };

  const onEdgeUpdate = (oldEdge: any, newConnection: any) =>
    setElements((els) => updateEdge(oldEdge, newConnection, els));

  return (
      <ReactFlow
        elements={elements}
        onConnect={onConnect}
        onLoad={setRfInstance}
        onNodeDragStop={handleSave}
        onDragEnd={handleSave}
        onMouseLeave={handleSave}
        onEdgeUpdate={onEdgeUpdate}
        nodeTypes={nodeTypes}
      >
        <CustomControls
          isDisabled={isLoading}
          onAutoFormat={handleAutoFormat}
          onRestartSession={setRestartModal.on}
        />
        <RightAlignedControls
          showFitView={true}
        />
        <Background color="#aaa" gap={DEFAULT_BG_GAP} />
        <RestartModal
          close={setRestartModal.off}
          isOpen={isRestartModalOpen}
        />
      </ReactFlow>
  );
};

export default Flow;
