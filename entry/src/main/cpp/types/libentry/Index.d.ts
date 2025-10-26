export const startKernel: (appDir: string, workspaceBaseDir: string, localIPs: string, osVer: string) => void;
export const isHttpServing: () => boolean;
export const disableFeature: (feature: string) => void;
export const unzip: (zipPath: string, dest: string) => void;
export const getAssetAbsPath: (relativePath: string) => string;
export const getCurrentWorkspacePath: () => string;
