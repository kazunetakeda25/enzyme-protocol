const common = {
  preset: '@enzymefinance/hardhat',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
};

function project(name: string, roots: string[]) {
  return {
    ...common,
    displayName: name,
    roots,
  };
}

const projects = [
  project('persistent', ['tests/persistent']),
  project('core', ['tests/release/core']),
  project('infrastructure', ['tests/release/infrastructure']),
  project('policy', ['tests/release/extensions/policy-manager']),
  project('integration', ['tests/release/extensions/integration-manager']),
  project('external', ['tests/release/extensions/external-position-manager']),
  project('fee', ['tests/release/extensions/fee-manager']),
  project('peripheral', ['tests/release/peripheral']),
  project('utils', ['tests/release/utils']),
  project('e2e', ['tests/release/e2e']),
];

export default {
  projects,
  testTimeout: 240000,
};
