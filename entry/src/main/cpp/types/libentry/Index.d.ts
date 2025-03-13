export const startKernel: (appDir: string, workspaceBaseDir: string, ips: string) => void;

export const isHttpServing: () => boolean;

export const disableFeature: (feature: string) => void;

export const unzip: (zipPath: string, dest: string) => void;
