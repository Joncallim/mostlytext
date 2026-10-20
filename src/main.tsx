import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

const root = document.getElementById('root')!
const app = <React.StrictMode><App /></React.StrictMode>

// dist/index.html carries the prerendered home page. The hash-routed roadmap
// renders fresh rather than hydrating markup that belongs to another view.
if (root.firstElementChild && !window.location.hash.startsWith('#/roadmap')) {
  ReactDOM.hydrateRoot(root, app)
} else {
  root.replaceChildren()
  ReactDOM.createRoot(root).render(app)
}
document.documentElement.classList.remove('prerender-pending')
