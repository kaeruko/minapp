from __future__ import annotations

import json
import re

from errors import ApiProblem

_WEB_BRIDGE_NONCE_RE = re.compile(r"^[A-Za-z0-9_-]{32,64}$")
_PORTAL_ORIGIN_RE = re.compile(r"^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?$")


def inject_web_runtime_bridge(
    index_html: bytes,
    *,
    parent_origin: str,
    bridge_nonce: str,
) -> bytes:
    if not isinstance(index_html, bytes):
        raise TypeError("index_html must be bytes")
    if _PORTAL_ORIGIN_RE.fullmatch(parent_origin) is None:
        raise RuntimeError("Web Runtime parent origin is invalid")
    if _WEB_BRIDGE_NONCE_RE.fullmatch(bridge_nonce) is None:
        raise RuntimeError("Web Runtime bridge nonce is invalid")
    try:
        source = index_html.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ApiProblem(
            409,
            "authoring_player_web_incompatible",
            "Web Authoring Player index.html must be valid UTF-8.",
        ) from exc

    bootstrap = _runtime_bootstrap_javascript(parent_origin, bridge_nonce)
    return (source + "\n<script>\n" + bootstrap + "\n</script>\n").encode("utf-8")


def _runtime_bootstrap_javascript(parent_origin: str, bridge_nonce: str) -> str:
    origin_json = json.dumps(parent_origin, ensure_ascii=True)
    nonce_json = json.dumps(bridge_nonce, ensure_ascii=True)
    return f"""(() => {{
  'use strict';
  const VERSION = 1;
  const CHANNEL = 'minapp.web';
  const PARENT_ORIGIN = {origin_json};
  const NONCE = {nonce_json};
  const REQUEST_ID = /^[A-Za-z0-9_-]{{1,64}}$/;
  const STATE_KEY = /^[a-z][a-z0-9_.-]{{0,63}}$/;

  if (window.parent === window) {{
    throw new Error('Web Runtime bridge requires a parent iframe host.');
  }}
  if (window.minapp !== undefined) {{
    throw new Error('Web Runtime bridge found an existing window.minapp value.');
  }}

  const pending = new Map();
  let nextId = 1;

  class MinAppRuntimeError extends Error {{
    constructor(status, code, message) {{
      super(message);
      this.name = 'MinAppRuntimeError';
      this.status = status;
      this.code = code;
    }}
  }}

  const isPlainObject = (value) => (
    typeof value === 'object' && value !== null && !Array.isArray(value)
  );

  const send = (request) => new Promise((resolve, reject) => {{
    const id = String(nextId++);
    if (!REQUEST_ID.test(id)) {{
      reject(new MinAppRuntimeError(0, 'bridge_request_id_exhausted', 'Web Runtime request id is invalid.'));
      return;
    }}
    const message = Object.assign({{
      channel: CHANNEL,
      nonce: NONCE,
      version: VERSION,
      type: 'request',
      id,
    }}, request);
    pending.set(id, {{ resolve, reject }});
    try {{
      window.parent.postMessage(message, PARENT_ORIGIN);
    }} catch (error) {{
      pending.delete(id);
      reject(new MinAppRuntimeError(0, 'bridge_unavailable', String(error)));
    }}
  }});

  window.addEventListener('message', (event) => {{
    if (event.source !== window.parent || event.origin !== PARENT_ORIGIN) return;
    const response = event.data;
    if (!isPlainObject(response) ||
        response.channel !== CHANNEL ||
        response.nonce !== NONCE ||
        response.version !== VERSION ||
        response.type !== 'response' ||
        typeof response.id !== 'string' ||
        !REQUEST_ID.test(response.id)) {{
      return;
    }}
    const waiter = pending.get(response.id);
    if (!waiter) return;
    pending.delete(response.id);
    if (response.ok === true) {{
      if (Object.keys(response).sort().join(',') !== 'channel,id,nonce,ok,result,type,version') {{
        waiter.reject(new MinAppRuntimeError(0, 'invalid_bridge_response', 'Web Runtime success response fields are invalid.'));
        return;
      }}
      waiter.resolve(response.result);
      return;
    }}
    const error = response.error;
    if (response.ok !== false ||
        Object.keys(response).sort().join(',') !== 'channel,error,id,nonce,ok,type,version' ||
        !isPlainObject(error) ||
        Object.keys(error).sort().join(',') !== 'code,message,status' ||
        typeof error.status !== 'number' ||
        typeof error.code !== 'string' || error.code.length === 0 ||
        typeof error.message !== 'string' || error.message.length === 0) {{
      waiter.reject(new MinAppRuntimeError(0, 'invalid_bridge_response', 'Web Runtime error response is invalid.'));
      return;
    }}
    waiter.reject(new MinAppRuntimeError(error.status, error.code, error.message));
  }});

  const validateKey = (key) => {{
    if (typeof key !== 'string' || !STATE_KEY.test(key)) {{
      throw new MinAppRuntimeError(0, 'invalid_state_key', 'State key is invalid.');
    }}
    return key;
  }};

  const state = Object.freeze({{
    get: (key) => {{
      try {{ return send({{ method: 'state.get', key: validateKey(key) }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
    set: (key, value) => {{
      try {{ return send({{ method: 'state.set', key: validateKey(key), value }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
    delete: (key) => {{
      try {{ return send({{ method: 'state.delete', key: validateKey(key) }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
  }});
  const userState = Object.freeze({{
    get: (key) => {{
      try {{ return send({{ method: 'userState.get', key: validateKey(key) }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
    set: (key, value) => {{
      try {{ return send({{ method: 'userState.set', key: validateKey(key), value }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
    delete: (key) => {{
      try {{ return send({{ method: 'userState.delete', key: validateKey(key) }}); }}
      catch (error) {{ return Promise.reject(error); }}
    }},
  }});

  Object.defineProperty(window, 'minapp', {{
    configurable: true,
    value: Object.freeze({{ version: VERSION, state, userState }}),
  }});
  window.dispatchEvent(new Event('minappready'));
}})();"""
