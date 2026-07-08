function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}. ` +
        `Ensure it is passed as a --build-arg during docker build.`
    );
  }
  return value;
}

export const TASK_API_URL = requireEnv("REACT_APP_BACKEND_URL");
export const AUTH_API_URL = requireEnv("REACT_APP_AUTH_URL");
export const NOTIFICATIONS_API_URL = requireEnv("REACT_APP_NOTIFICATIONS_URL");
