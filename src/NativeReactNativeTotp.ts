import { TurboModuleRegistry, type TurboModule } from 'react-native';

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

export interface Spec extends TurboModule {
  initFynoConfig(wsid: string, distinctId: string): Promise<boolean>;

  registerTenant(
    tenantId: string,
    tenantLabel: string,
    totpToken: string
  ): Promise<boolean>;

  setConfig(
    tenantId: string,
    config: {
      digits: number;
      period: number;
      algorithm: string;
    }
  ): Promise<boolean>;

  getTotp(tenantId: string): Promise<string | null>;

  deleteTenant(tenantId: string): Promise<boolean>;

  fetchActiveTenants(): Promise<ActiveTenant[]>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('ReactNativeTotp');
