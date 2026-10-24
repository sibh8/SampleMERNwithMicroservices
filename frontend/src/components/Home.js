import React, { useEffect, useState } from "react";
import axios from "axios";

// Resolve backend URLs from runtime config (window.__APP_CONFIG__) with
// build-time env vars and localhost defaults as fallbacks.
const runtimeConfig =
  (typeof window !== "undefined" && window.__APP_CONFIG__) || {};
const HELLO_SERVICE_URL =
  runtimeConfig.HELLO_SERVICE_URL ||
  process.env.REACT_APP_HELLO_SERVICE_URL ||
  "http://localhost:3001";
const PROFILE_SERVICE_URL =
  runtimeConfig.PROFILE_SERVICE_URL ||
  process.env.REACT_APP_PROFILE_SERVICE_URL ||
  "http://localhost:3002";

function Home() {
  const [message, setMessage] = useState("");
  const [profile, setProfile] = useState([]);

  useEffect(() => {
    axios
      .get(`${HELLO_SERVICE_URL}/`)
      .then((response) => {
        setMessage(response.data.msg);
      })
      .catch((error) => console.error("Error fetching data:", error));
  }, []);

  useEffect(() => {
    axios
      .get(`${PROFILE_SERVICE_URL}/fetchUser`)
      .then((response) => {
        setProfile(response.data);
        
      })
      .catch((error) => console.error("Error fetching data:", error));
  },[]);

  

  return (
    <div className="App">
      <h1>{message}</h1>
      <div>
        <h2>Profile</h2>
        {
        profile.map((user) => {
            console.log('user', user)
          return (
            <div>
              <h3>Name: {user.name}</h3>
              <h3>Age: {user.age}</h3>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default Home;
