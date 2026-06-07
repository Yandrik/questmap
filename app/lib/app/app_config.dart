const appTitle = 'Meander';
const appApiBaseUrl = String.fromEnvironment(
  'QUESTMAP_API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);
const mapStyleAsset = 'assets/omt_style.json';
const tileUserAgent = 'dev.meander.meander';
