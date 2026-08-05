/*
 * SiYuan - 源于思考，饮水思源
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { mdns } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';

interface LANSyncDiscoveryInfo {
  instance: string;
  serviceType: string;
  port: number;
  txt: Record<string, string>;
}

class LANSyncServiceAttribute {
  key: string;
  value: number[];

  constructor(key: string, value: number[]) {
    this.key = key;
    this.value = value;
  }
}

export class LANSyncMDNS {
  static readonly shared = new LANSyncMDNS();

  private context?: common.UIAbilityContext;
  private discoveryService?: mdns.DiscoveryService;
  private publishedService?: mdns.LocalServiceInfo;
  private publishedInfo = '';
  private refreshTimer = -1;
  private generation = 0;
  private operation: Promise<void> = Promise.resolve();
  private discoveredServices: Map<string, mdns.LocalServiceInfo> = new Map();
  private lastPeerRefresh = 0;

  private constructor() {
  }

  start(context: common.UIAbilityContext): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    this.context = context;
    this.generation++;
    this.refresh();
    this.refreshTimer = setInterval(() => this.refresh(), 5000);
  }

  stop(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.generation++;
    const generation = this.generation;
    this.enqueue(async () => this.stopDiscovery(generation, true));
  }

  private refresh(): void {
    const generation = this.generation;
    const rawInfo = napi.lanSyncDiscoveryInfo() ?? '';
    if (!rawInfo) {
      this.enqueue(async () => this.stopDiscovery(generation, false));
      return;
    }

    let info: LANSyncDiscoveryInfo;
    try {
      info = JSON.parse(rawInfo) as LANSyncDiscoveryInfo;
    } catch (error) {
      hilog.error(0x0000, 'siyuan', 'parse LAN sync discovery info failed: ' + error);
      return;
    }
    if (!info.instance || !info.serviceType || info.port < 1) {
      return;
    }

    if (rawInfo !== this.publishedInfo) {
      this.enqueue(async () => this.updateAdvertisement(generation, rawInfo, info));
    }
    if (Date.now() - this.lastPeerRefresh >= 30000) {
      this.lastPeerRefresh = Date.now();
      for (const service of this.discoveredServices.values()) {
        this.resolvePeer(service, generation);
      }
    }
  }

  private enqueue(operation: () => Promise<void>): void {
    this.operation = this.operation.then(operation).catch((error: BusinessError) => {
      hilog.error(0x0000, 'siyuan', 'update LAN sync MDNS failed: ' + error);
    });
  }

  private async updateAdvertisement(generation: number, rawInfo: string,
    info: LANSyncDiscoveryInfo): Promise<void> {
    if (generation !== this.generation || !this.context) {
      return;
    }
    this.ensureDiscovery();
    if (this.publishedService) {
      try {
        await mdns.removeLocalService(this.context, this.publishedService);
      } catch (error) {
        hilog.warn(0x0000, 'siyuan', 'remove LAN sync MDNS service failed: ' + error);
      }
      this.publishedService = undefined;
      this.publishedInfo = '';
    }
    if (generation !== this.generation || !this.context) {
      return;
    }

    const attributes: mdns.ServiceAttribute[] = [];
    for (const key of Object.keys(info.txt)) {
      attributes.push(new LANSyncServiceAttribute(key, this.stringToBytes(info.txt[key])));
    }
    const service: mdns.LocalServiceInfo = {
      serviceType: this.normalizeServiceType(info.serviceType),
      serviceName: info.instance,
      port: info.port,
      serviceAttribute: attributes
    };
    try {
      this.publishedService = await mdns.addLocalService(this.context, service);
      if (generation === this.generation) {
        this.publishedInfo = rawInfo;
      } else {
        await mdns.removeLocalService(this.context, this.publishedService);
        this.publishedService = undefined;
      }
    } catch (error) {
      this.publishedService = undefined;
      this.publishedInfo = '';
      hilog.warn(0x0000, 'siyuan', 'publish LAN sync MDNS service failed: ' + error);
    }
  }

  private ensureDiscovery(): void {
    if (this.discoveryService || !this.context) {
      return;
    }
    const service = mdns.createDiscoveryService(this.context, '_siyuan-sync._tcp');
    service.on('serviceFound', this.onServiceFound);
    service.on('serviceLost', this.onServiceLost);
    service.startSearchingMDNS();
    this.discoveryService = service;
  }

  private async stopDiscovery(generation: number, clearContext: boolean): Promise<void> {
    if (generation !== this.generation) {
      return;
    }
    if (this.discoveryService) {
      this.discoveryService.stopSearchingMDNS();
      this.discoveryService.off('serviceFound', this.onServiceFound);
      this.discoveryService.off('serviceLost', this.onServiceLost);
      this.discoveryService = undefined;
    }
    for (const instance of this.discoveredServices.keys()) {
      napi.removeLANSyncPeer(instance);
    }
    this.discoveredServices.clear();
    this.lastPeerRefresh = 0;
    if (this.publishedService && this.context) {
      try {
        await mdns.removeLocalService(this.context, this.publishedService);
      } catch (error) {
        hilog.warn(0x0000, 'siyuan', 'remove LAN sync MDNS service failed: ' + error);
      }
    }
    this.publishedService = undefined;
    this.publishedInfo = '';
    if (clearContext) {
      this.context = undefined;
    }
  }

  private readonly onServiceFound = (service: mdns.LocalServiceInfo): void => {
    if (!service.serviceName || service.serviceName === this.publishedService?.serviceName) {
      return;
    }
    this.discoveredServices.set(service.serviceName, service);
    this.resolvePeer(service, this.generation);
  };

  private readonly onServiceLost = (service: mdns.LocalServiceInfo): void => {
    if (!service.serviceName) {
      return;
    }
    this.discoveredServices.delete(service.serviceName);
    napi.removeLANSyncPeer(service.serviceName);
  };

  private resolvePeer(service: mdns.LocalServiceInfo, generation: number): void {
    const context = this.context;
    if (!context || generation !== this.generation) {
      return;
    }
    mdns.resolveLocalService(context, service).then((resolved) => {
      if (generation !== this.generation || !resolved.host?.address || resolved.host.address.includes(':')) {
        return;
      }
      const txt: Record<string, string> = {};
      for (const attribute of resolved.serviceAttribute ?? []) {
        txt[attribute.key] = this.bytesToString(attribute.value);
      }
      napi.addLANSyncPeer(resolved.serviceName, resolved.host.address, resolved.port, JSON.stringify(txt));
    }).catch((error: BusinessError) => {
      hilog.debug(0x0000, 'siyuan', 'resolve LAN sync MDNS service failed: ' + error);
    });
  }

  private normalizeServiceType(serviceType: string): string {
    return serviceType.endsWith('.') ? serviceType.substring(0, serviceType.length - 1) : serviceType;
  }

  private stringToBytes(value: string): number[] {
    const ret: number[] = [];
    for (let i = 0; i < value.length; i++) {
      ret.push(value.charCodeAt(i));
    }
    return ret;
  }

  private bytesToString(value: number[]): string {
    let ret = '';
    for (const current of value) {
      ret += String.fromCharCode(current);
    }
    return ret;
  }
}
