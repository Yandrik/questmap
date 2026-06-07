const appTitle = 'Meander';
const appApiBaseUrl = String.fromEnvironment(
  'QUESTMAP_API_BASE_URL',
  defaultValue: 'https://back.hack5.yandrik.dev',
);
const mapStyleAsset = 'assets/omt_style.json';
const tileUserAgent = 'dev.meander.meander';
