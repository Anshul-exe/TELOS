import React, { useState } from "react";
import { Paper, TextField, Button } from "@material-ui/core";
import { useAuth } from "../context/AuthContext";
import "./AuthPage.css";

const ERROR_MESSAGES = {
  "email and password are required": "Please enter both email and password.",
  "email already registered": "This email is already registered. Try logging in.",
  "invalid credentials": "Invalid email or password.",
  "internal server error": "Something went wrong. Please try again.",
};

function formatError(err) {
  if (err.response && err.response.data && err.response.data.error) {
    return ERROR_MESSAGES[err.response.data.error] || err.response.data.error;
  }
  if (err.request) {
    return "Unable to connect. Please check your connection.";
  }
  return "Something went wrong. Please try again.";
}

function AuthPage() {
  const { login, register } = useAuth();
  const [isRegister, setIsRegister] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setSuccess("");
    setLoading(true);

    try {
      if (isRegister) {
        await register(email, password);
        setSuccess("Account created! You can now sign in.");
        setIsRegister(false);
        setPassword("");
      } else {
        await login(email, password);
        // On success, AuthContext updates and App re-renders to show TaskView
      }
    } catch (err) {
      setError(formatError(err));
    } finally {
      setLoading(false);
    }
  };

  const toggleMode = () => {
    setIsRegister(!isRegister);
    setError("");
    setSuccess("");
  };

  return (
    <div className="auth-page">
      <div className="auth-container">
        <div className="auth-brand">
          <h1 className="auth-logo">TELOS</h1>
          <p className="auth-tagline">Async microservice platform</p>
        </div>
        <Paper elevation={3} className="auth-card">
          <h2 className="auth-title">
            {isRegister ? "Create Account" : "Welcome Back"}
          </h2>
          <p className="auth-subtitle">
            {isRegister
              ? "Sign up to start managing tasks"
              : "Sign in to your account"}
          </p>

          {error && <div className="auth-error">{error}</div>}
          {success && <div className="auth-success">{success}</div>}

          <form onSubmit={handleSubmit} className="auth-form">
            <TextField
              id="auth-email"
              label="Email"
              type="email"
              variant="outlined"
              size="small"
              fullWidth
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="auth-field"
              disabled={loading}
              autoComplete="email"
            />
            <TextField
              id="auth-password"
              label="Password"
              type="password"
              variant="outlined"
              size="small"
              fullWidth
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="auth-field"
              disabled={loading}
              autoComplete={isRegister ? "new-password" : "current-password"}
            />
            <Button
              id="auth-submit"
              type="submit"
              variant="contained"
              color="primary"
              fullWidth
              disabled={loading}
              className="auth-submit"
            >
              {loading
                ? isRegister
                  ? "Creating Account\u2026"
                  : "Signing In\u2026"
                : isRegister
                ? "Create Account"
                : "Sign In"}
            </Button>
          </form>

          <div className="auth-toggle">
            <span>
              {isRegister
                ? "Already have an account?"
                : "Don\u2019t have an account?"}
            </span>
            <button
              type="button"
              onClick={toggleMode}
              className="auth-toggle-btn"
              disabled={loading}
            >
              {isRegister ? "Sign In" : "Sign Up"}
            </button>
          </div>
        </Paper>
      </div>
    </div>
  );
}

export default AuthPage;
