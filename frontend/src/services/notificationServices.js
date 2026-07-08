import axios from "axios";
import { NOTIFICATIONS_API_URL } from "../config";

export function getNotifications() {
  return axios.get(NOTIFICATIONS_API_URL);
}
