import React, { useState, useEffect, useCallback } from "react";
import { Paper } from "@material-ui/core";
import { getNotifications } from "../services/notificationServices";
import "./Notifications.css";

const EVENT_CONFIG = {
  "task.created": { icon: "\uD83D\uDCCB", label: "Task created" },
  "task.completed": { icon: "\u2705", label: "Task completed" },
  "task.updated": { icon: "\u270F\uFE0F", label: "Task updated" },
};

function formatTimeAgo(dateString) {
  const now = new Date();
  const date = new Date(dateString);
  const seconds = Math.floor((now - date) / 1000);

  if (seconds < 0) return "just now";
  if (seconds < 60) return "just now";

  const minutes = Math.floor(seconds / 60);
  if (minutes === 1) return "1 min ago";
  if (minutes < 60) return `${minutes} min ago`;

  const hours = Math.floor(minutes / 60);
  if (hours === 1) return "1 hour ago";
  if (hours < 24) return `${hours} hours ago`;

  const days = Math.floor(hours / 24);
  if (days === 1) return "1 day ago";
  return `${days} days ago`;
}

function Notifications({ isOpen, onClose }) {
  const [notifications, setNotifications] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

  const fetchNotifications = useCallback(async () => {
    try {
      const { data } = await getNotifications();
      setNotifications(data);
      setError(null);
    } catch (err) {
      setError("Unable to load notifications");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!isOpen) return;

    let mounted = true;

    const doFetch = async () => {
      if (!mounted) return;
      await fetchNotifications();
    };

    setLoading(true);
    doFetch();
    const interval = setInterval(doFetch, 15000);

    return () => {
      mounted = false;
      clearInterval(interval);
    };
  }, [isOpen, fetchNotifications]);

  if (!isOpen) return null;

  return (
    <div className="notifications-overlay" onClick={onClose}>
      <Paper
        elevation={4}
        className="notifications-panel"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="notifications-header">
          <h3>Notifications</h3>
          <button
            className="notifications-close"
            onClick={onClose}
            aria-label="Close notifications"
          >
            &#x2715;
          </button>
        </div>
        <div className="notifications-body">
          {loading && (
            <p className="notifications-status">Loading notifications\u2026</p>
          )}
          {error && !loading && (
            <p className="notifications-status notifications-error-text">
              {error}
            </p>
          )}
          {!loading && !error && notifications.length === 0 && (
            <p className="notifications-status">
              No notifications yet. Create or complete a task to see events
              here.
            </p>
          )}
          {!loading &&
            notifications.map((n) => {
              const config = EVENT_CONFIG[n.event] || {
                icon: "\uD83D\uDD14",
                label: n.event,
              };
              return (
                <div key={n._id} className="notification-item">
                  <span className="notification-icon">{config.icon}</span>
                  <div className="notification-content">
                    <span className="notification-label">{config.label}</span>
                    <span className="notification-message">{n.message}</span>
                    <span className="notification-time">
                      {formatTimeAgo(n.receivedAt)}
                    </span>
                  </div>
                </div>
              );
            })}
        </div>
      </Paper>
    </div>
  );
}

export default Notifications;
