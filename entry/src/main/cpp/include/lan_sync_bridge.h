/*
 * SiYuan - 源于思考，饮水思源
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#ifndef SIYUAN_LAN_SYNC_BRIDGE_H
#define SIYUAN_LAN_SYNC_BRIDGE_H

#include "libkernel.h"

#ifdef __cplusplus
extern "C" {
#endif

extern char *LANSyncDiscoveryInfo(void) __attribute__((weak));
extern GoUint8 AddLANSyncPeer(char *instance, char *address, GoInt port, char *txtJSON) __attribute__((weak));
extern GoUint8 RemoveLANSyncPeer(char *instance) __attribute__((weak));
extern GoUint8 LANSyncActive(void) __attribute__((weak));

#ifdef __cplusplus
}
#endif

#endif
