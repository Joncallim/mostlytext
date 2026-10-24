import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { routeFromLocation, viewOf } from './route'
import './index.css'

const root = document.getElementById('root')!
const app = <React.StrictMode><App /></React.StrictMode>

// The HTML is prerendered for one view (data-prerendered-view on <html>). Hydrate
// it when the URL asks for that view; otherwise render fresh, e.g. for
// /#/roadmap/after-1, rather than hydrate markup that belongs to another view.
if (root.firstElementChild && viewOf(routeFromLocation()) === document.documentElement.dataset.prerenderedView) {
  ReactDOM.hydrateRoot(root, app)
} else {
  root.replaceChildren()
  ReactDOM.createRoot(root).render(app)
}
document.documentElement.classList.remove('prerender-pending')
