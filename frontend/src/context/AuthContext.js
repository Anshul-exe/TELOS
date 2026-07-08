import React, { createContext, useContext, useState, useCallback } from "react";
import {
  login as loginApi,
  register as registerApi,
} from "../services/authServices";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [token, setToken] = useState(null);
  const [user, setUser] = useState(null);

  const login = useCallback(async (email, password) => {
    const { data } = await loginApi(email, password);
    setToken(data.token);
    // Decode JWT payload (base64url) to extract user info for display.
    // No cryptographic verification needed client-side — the server already
    // verified credentials before issuing the token.
    const payload = JSON.parse(atob(data.token.split(".")[1]));
    setUser({ userId: payload.userId, email: payload.email });
  }, []);

  const register = useCallback(async (email, password) => {
    const { data } = await registerApi(email, password);
    return data; // { id, email } — caller navigates to login on success
  }, []);

  const logout = useCallback(() => {
    setToken(null);
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider value={{ token, user, login, register, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
