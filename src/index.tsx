import ReactNativeTotp from './NativeReactNativeTotp';

export function initFynoConfig(
  wsid: string,
  distinctId: string
): Promise<boolean> {
  return ReactNativeTotp.initFynoConfig(wsid, distinctId);
}

export function registerTenant(
  tenantId: string,
  tenantLabel: string,
  totpToken: string
): Promise<boolean> {
  return ReactNativeTotp.registerTenant(tenantId, tenantLabel, totpToken);
}

export function setConfig(
  tenantId: string,
  config: {
    digits: number;
    period: number;
    algorithm: string;
  }
): Promise<boolean> {
  return ReactNativeTotp.setConfig(tenantId, config);
}

export function getTotp(tenantId: string): Promise<string | null> {
  return ReactNativeTotp.getTotp(tenantId);
}

export function deleteTenant(tenantId: string): Promise<boolean> {
  return ReactNativeTotp.deleteTenant(tenantId);
}

export type TotpConfig = {
  digits: number;
  period: number;
  algorithm: string;
};

export type ActiveTenant = {
  tenantId: string;
  tenantLabel: string;
  config: TotpConfig | null;
};

export function fetchActiveTenants(): Promise<ActiveTenant[]> {
  return ReactNativeTotp.fetchActiveTenants();
}
