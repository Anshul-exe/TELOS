import React from "react";
import ReactDOM from "react-dom";
import "./index.css";
import App from "./App";
import { AuthProvider } from "./context/AuthContext";

ReactDOM.render(
  <React.StrictMode>
    <div className="app-wrapper">
      <AuthProvider>
        <App />
      </AuthProvider>
    </div>
  </React.StrictMode>,
  document.getElementById("root")
);
