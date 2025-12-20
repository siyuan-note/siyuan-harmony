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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

export const startKernel: (appDir: string, workspaceBaseDir: string, localIPs: string, osVer: string) => void;
export const isHttpServing: () => boolean;
export const disableFeature: (feature: string) => void;
export const unzip: (zipPath: string, dest: string) => void;
export const getAssetAbsPath: (relativePath: string) => string;
export const getCurrentWorkspacePath: () => string;
export const exit: () => void;