/**
 * Application Entry Point
 *
 * Initializes the React application and renders the main App component
 * into the DOM.
 *
 * @module main
 */

import { createRoot } from "react-dom/client";
import App from "./App";

// Get the root element and create a React root
const rootApp = createRoot(document.getElementById("root") as HTMLElement);

// Render the application
rootApp.render(<App />);
