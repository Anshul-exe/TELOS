import React, { useState } from "react";
import { useAuth } from "./context/AuthContext";
import AuthPage from "./components/AuthPage";
import TaskView from "./components/TaskView";
import Notifications from "./components/Notifications";
import "./App.css";

function App() {
  const { user, logout } = useAuth();
  const [showNotifications, setShowNotifications] = useState(false);

  if (!user) {
    return <AuthPage />;
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">TELOS</h1>
        <div className="header-actions">
          <button
            id="notifications-btn"
            className="header-btn notification-btn"
            onClick={() => setShowNotifications(!showNotifications)}
            title="Notifications"
          >
            <span className="notification-bell" role="img" aria-label="notifications">
              &#x1F514;
            </span>
          </button>
          <span className="user-email">{user.email}</span>
          <button
            id="logout-btn"
            className="header-btn logout-btn"
            onClick={logout}
          >
            Sign Out
          </button>
        </div>
      </header>
      <div className="main-content">
        <TaskView />
      </div>
      <Notifications
        isOpen={showNotifications}
        onClose={() => setShowNotifications(false)}
      />
    </div>
  );
}

export default App;
