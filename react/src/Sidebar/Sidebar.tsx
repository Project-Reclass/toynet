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
import { useState } from 'react';
import { useHistory } from 'react-router-dom';

import ReclassLogo from '../assets/PR-Icon-Square-FullColor.png';
import { Avatar, Box, Flex, Stack } from '@chakra-ui/react';
import styled from '@emotion/styled';
import {
  CalendarIcon,
  ArrowLeftIcon,
} from '@chakra-ui/icons';

interface StyledNavProps {
  isMenuOpen: boolean;
};

const StyledNav = styled.nav`
  z-index: 3;
  height: 100vh;
  position: fixed;
  left: 0;
  background: rgb(24, 21, 21);
  transition: width 200ms ease;
  width: ${({ isMenuOpen }: StyledNavProps) => isMenuOpen ? '10rem' : '5rem'};

  ul {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    height: 100%;
  }
`;

const StyledNavItem = styled.div`
  margin-top: auto;
  transition: .1s all linear;

  &:hover {
    color: white;
    border-left: solid 3px teal;
  }
`;

const StyledNavIcon = styled.div`
  margin-left: 1rem;
  display: flex;
  align-items: center;
  height: 3rem;
  text-decoration: none;
  cursor: pointer;

  opacity: 0.9;
  transition: opacity 100ms;

  &:hover {
    stroke-width: 0;
    stroke: #fff;
    opacity: 0.95;
  }
`;

const StyledSvg = styled.span`
  margin: 0 0.30rem;

  &:hover {
   cursor: pointer;
  }
`;

const StyledLinkText = styled.span`
  color: white;
  filter: grayscale(100%) opacity(0.7);
  transition: color 200ms;

  transition: opacity 200ms;
  white-space: nowrap;
  visibility: ${({ isMenuOpen }: StyledNavProps) => isMenuOpen ? 'visible' : 'hidden'};
  opacity: ${({ isMenuOpen }: StyledNavProps) => isMenuOpen ? '1' : '0'};

  &:hover {
    filter: grayscale(0%) opacity(1);
    text-decoration: none;
    color: white;
  }
`;

const Sidebar = () => {
  const history = useHistory();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [enableHref, setEnableHref] = useState(false);

  function toggleMenu() {
    setIsMenuOpen(prevMenu => !prevMenu);
    setEnableHref(prevEnableHref => !prevEnableHref);
  }

  const goToPageOnEnableHref = (path: string) => {
    if (enableHref) {
      history.push(path);
    }
  };

  return (
    <Box minWidth='5rem' height='100vh'>
      <StyledNav isMenuOpen={isMenuOpen} onMouseOver={toggleMenu} onMouseOut={toggleMenu}>
        <Flex direction='column' justifyContent='space-between' height='100%' paddingY='1rem'>
          <Stack spacing={1}>
            <StyledNavIcon onClick={() => goToPageOnEnableHref('/')}>
              <Avatar src={ReclassLogo} marginBottom='1rem' backgroundColor='white'/>
            </StyledNavIcon>
            <StyledNavItem onClick={() => goToPageOnEnableHref('/dashboard/1')}>
              <StyledNavIcon>
                <StyledSvg>
                  <CalendarIcon w='30px' h='30px' color='white' />
                </StyledSvg>
                <StyledLinkText isMenuOpen={isMenuOpen}>
                  Curriculum
                </StyledLinkText>
              </StyledNavIcon>
            </StyledNavItem>
          </Stack>
          <Stack spacing={3}>
            {/* <StyledNavItem onClick={() => goToPageOnEnableHref('/blank')}>
              <StyledNavIcon>
                <StyledSvg>
                  <SettingsIcon w='28px' h='28px' color='white'/>
                </StyledSvg>
                <StyledLinkText isMenuOpen={isMenuOpen}>
                  Profile
                </StyledLinkText>
              </StyledNavIcon>
            </StyledNavItem>
            <StyledNavItem onClick={() => goToPageOnEnableHref('/blank')}>
              <StyledNavIcon>
                <StyledSvg>
                  <QuestionIcon w='28px' h='28px' color='white'/>
                </StyledSvg>
                <StyledLinkText isMenuOpen={isMenuOpen}>
                  FAQ
                </StyledLinkText>
              </StyledNavIcon>
            </StyledNavItem> */}
            <StyledNavItem onClick={() => goToPageOnEnableHref('/')}>
              <StyledNavIcon>
                <StyledSvg>
                  <ArrowLeftIcon w='28px' h='28px' color='white'/>
                </StyledSvg>
                <StyledLinkText isMenuOpen={isMenuOpen}>
                  Home
                </StyledLinkText>
              </StyledNavIcon>
            </StyledNavItem>
          </Stack>
        </Flex>
      </StyledNav>
    </Box>
  );
};

export default Sidebar;