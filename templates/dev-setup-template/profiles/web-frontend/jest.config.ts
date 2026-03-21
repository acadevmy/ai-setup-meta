export default {
  testEnvironment: 'jsdom',
  setupFilesAfterSetup: ['<rootDir>/jest.setup.ts'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  coverageThreshold: {
    global: { lines: 70, functions: 70, branches: 60 },
    './src/services/': { lines: 80 },
    './src/utils/': { lines: 90 },
  },
};
