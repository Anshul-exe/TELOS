import axios from "axios";
import { AUTH_API_URL } from "../config";

export function login(email, password) {
  return axios.post(`${AUTH_API_URL}/login`, { email, password });
}

export function register(email, password) {
  return axios.post(`${AUTH_API_URL}/register`, { email, password });
}
