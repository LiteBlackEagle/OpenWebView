unit Zplug;

interface

uses
  zhex;

const
  zDB_script =
  '''
  if (typeof window.ZDBInitialized === 'undefined') {
      window.ZDB_READY = false;
      window.ZDBInitialized = true;
      (function() {
          const DB_NAME = 'ZWebview_Persistence_DB';
          let DB_VERSION = 1;

          const EXPECTED_STORES = [
              'zKernelScripts',
              'zKernelState',
              'zKeyMapperState',
              'zMediaPopupState',
              'zMiniAlbumItems',
              'zContextMenu2State'
          ];

          let _dbPromise = null;

          function getDBConnection(newVersion) {
              return new Promise((resolve, reject) => {
                  const request = indexedDB.open(DB_NAME, newVersion);
                  request.onerror = event => reject(event.target.error);
                  request.onsuccess = event => resolve(event.target.result);
                  request.onupgradeneeded = event => {
                      const db = event.target.result;
                      const existingStores = Array.from(db.objectStoreNames);
                      console.log('[zDB] onupgradeneeded triggered. Applying schema...');

                      const storesToAdd = EXPECTED_STORES.filter(s => !existingStores.includes(s));
                      storesToAdd.forEach(storeName => {
                          if (!db.objectStoreNames.contains(storeName)) {
                              db.createObjectStore(storeName, { keyPath: 'id' });
                              console.log(`[zDB]   -> Created object store: '${storeName}'`);
                          }
                      });

                      const storesToRemove = existingStores.filter(s => !EXPECTED_STORES.includes(s));
                      storesToRemove.forEach(storeName => {
                          if (db.objectStoreNames.contains(storeName)) {
                              db.deleteObjectStore(storeName);
                              console.log(`[zDB]   -> Removed obsolete object store: '${storeName}'`);
                          }
                      });
                  };
              });
          }

          async function initializeDB() {
              console.log('[zDB] Initializing database...');
              try {
                  // Mở để kiểm tra phiên bản và các store hiện có
                  const dbForCheck = await new Promise((resolve, reject) => {
                      const request = indexedDB.open(DB_NAME);
                      request.onerror = e => resolve(null); // Nếu lỗi, có thể DB chưa tồn tại
                      request.onsuccess = e => resolve(e.target.result);
                  });

                  let needsUpgrade = false;
                  if (!dbForCheck) {
                      needsUpgrade = true;
                      DB_VERSION = 1;
                  } else {
                      DB_VERSION = dbForCheck.version;
                      const existingStores = Array.from(dbForCheck.objectStoreNames);
                      dbForCheck.close();

                      const storesToAdd = EXPECTED_STORES.filter(s => !existingStores.includes(s));
                      const storesToRemove = existingStores.filter(s => !EXPECTED_STORES.includes(s));

                      if (storesToAdd.length > 0 || storesToRemove.length > 0) {
                          needsUpgrade = true;
                          DB_VERSION++;
                      }
                  }

                  if (needsUpgrade) {
                      console.log(`[zDB] Schema change detected. Opening with new version: ${DB_VERSION}`);
                      const db = await getDBConnection(DB_VERSION);
                      db.close();
                  } else {
                      console.log('[zDB] Database schema is up-to-date.');
                  }

                  // Tạo kết nối chính để sử dụng
                  _dbPromise = getDBConnection(DB_VERSION);

                  // Tạo API dùng chung
                  window.ZSharedDB = {
                      performTransaction: async (storeName, mode, action) => {
                          if (!EXPECTED_STORES.includes(storeName)) {
                               return Promise.reject(`[ZSharedDB] Error: Object store '${storeName}' is not defined in EXPECTED_STORES.`);
                          }
                          const db = await _dbPromise;
                          return new Promise((resolve, reject) => {
                              const transaction = db.transaction(storeName, mode);
                              transaction.onerror = event => reject(event.target.error);
                              const store = transaction.objectStore(storeName);
                              const request = action(store);
                              request.onsuccess = () => resolve(request.result);
                              request.onerror = event => reject(event.target.error);
                          });
                      }
                  };

                  console.log('[zDB] Database is ready.');
                  window.ZDB_READY = true;
                  document.dispatchEvent(new CustomEvent('ZDB_READY'));

              } catch (error) {
                  console.error('[zDB] Critical error during database initialization:', error);
              }
          }

          initializeDB();
      })();
  }
''';




const zContextMenu =
'''
if (typeof window.ZContextMenuInitialized === 'undefined') {
  window.ZContextMenuInitialized = true;
  (function() {
    const appState = {
      shadowHost: null,
      menuElement: null,
      isVisible: false,
      dom: {},
      positionObserver: null,
      lastRightClickedElement: null
    };
    const ICONS = {
      back: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>`,
      forward: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>`,
      home: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline></svg>`,
      reload: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"></polyline><polyline points="1 20 1 14 7 14"></polyline><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path></svg>`,
      trash: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`
    };
    let policy = window.trustedTypes?.createPolicy('z-context-menu-policy', { createHTML: string => string });
    const setHTML = (element, html) => { if (policy) element.innerHTML = policy.createHTML(html); else element.innerHTML = html; };
    function createView() {
      if (document.getElementById('z-context-menu-host')) return;
      if (!document.body) { setTimeout(createView, 50); return; }
      appState.shadowHost = document.createElement('div');
      appState.shadowHost.id = 'z-context-menu-host';
      document.body.appendChild(appState.shadowHost);
      const shadowRoot = appState.shadowHost.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent = `
        :host {
          --bg-color: rgba(28, 28, 28, 0.85); --blur: 16px; --text-color: #e0e0e0;
          --hover-bg-color: rgba(255, 255, 255, 0.1); --radius: 18px; --btn-size: 40px;
          --delete-hover-color: #ef4444;
        }
        .menu-container {
          position: fixed; display: none; z-index: 2147483647; background-color: var(--bg-color);
          backdrop-filter: blur(var(--blur)) saturate(1.2); -webkit-backdrop-filter: blur(var(--blur)) saturate(1.2);
          border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 4px 15px rgba(0,0,0,0.3);
          border-radius: var(--radius); padding: 6px; user-select: none; gap: 6px; opacity: 0;
          transform: scale(0.95); transition: all 0.15s ease;
        }
        .menu-container.visible { opacity: 1; transform: scale(1); }
        .menu-btn {
          width: var(--btn-size); height: var(--btn-size); display: flex; align-items: center; justify-content: center;
          border-radius: 50%; color: var(--text-color); cursor: pointer;
          transition: transform 0.15s ease, background-color 0.15s ease, color 0.15s ease;
          border: none; background: transparent; padding: 0;
        }
        .menu-btn:hover { transform: scale(1.1); background-color: var(--hover-bg-color); }
        #z-ctx-trash:hover { background-color: rgba(239, 68, 68, 0.2); color: var(--delete-hover-color); }
        .menu-btn:active { transform: scale(0.95); }
        .menu-btn[disabled] { opacity: 0.4; pointer-events: none; background-color: transparent; }
      `;
      shadowRoot.appendChild(style);
      appState.menuElement = document.createElement('div');
      appState.menuElement.className = 'menu-container';
      setHTML(appState.menuElement, `
        <button class="menu-btn" id="z-ctx-back" title="Back">${ICONS.back}</button>
        <button class="menu-btn" id="z-ctx-forward" title="Forward">${ICONS.forward}</button>
        <button class="menu-btn" id="z-ctx-trash" title="Deep Delete Element">${ICONS.trash}</button>
        <button class="menu-btn" id="z-ctx-home" title="Home">${ICONS.home}</button>
        <button class="menu-btn" id="z-ctx-reload" title="Reload">${ICONS.reload}</button>
      `);
      shadowRoot.appendChild(appState.menuElement);
      appState.dom = {
        home: shadowRoot.getElementById('z-ctx-home'), back: shadowRoot.getElementById('z-ctx-back'),
        forward: shadowRoot.getElementById('z-ctx-forward'), reload: shadowRoot.getElementById('z-ctx-reload'),
        trash: shadowRoot.getElementById('z-ctx-trash')
      };
    }
    function deepDeleteElement() {
        if (appState.lastRightClickedElement) { try { appState.lastRightClickedElement.remove(); } catch(e) { console.error("ZContextMenu: Failed to remove element.", e); } }
        hideMenu();
    }
    function hideMenu() {
      if (!appState.isVisible) return;
      if (appState.positionObserver) { appState.positionObserver.disconnect(); appState.positionObserver = null; }
      if (appState.menuElement) {
          appState.menuElement.classList.remove('visible');
          setTimeout(() => { if (!appState.isVisible && appState.menuElement) { appState.menuElement.style.display = 'none'; } }, 150);
      }
      appState.isVisible = false;
      appState.lastRightClickedElement = null;
    }
    function onContextMenu(event) {
      if (!appState.menuElement) createView();
      if (!appState.menuElement) return;
      if (appState.menuElement.contains(event.target)) return;
      appState.lastRightClickedElement = event.target;
      appState.dom.back.disabled = !(window.history.length > 1);
      appState.dom.forward.disabled = false;
      appState.dom.trash.disabled = !appState.lastRightClickedElement || appState.lastRightClickedElement === document.body || appState.lastRightClickedElement === document.documentElement;
      appState.menuElement.style.display = 'flex';
      const { offsetWidth: menuWidth, offsetHeight: menuHeight } = appState.menuElement;
      setTimeout(() => {
        const zCtx2Host = document.getElementById('z-context-menu2-host');
        const zCtx2Menu = zCtx2Host?.shadowRoot?.querySelector('.menu-container');
        if (zCtx2Menu && getComputedStyle(zCtx2Menu).display !== 'none') {
            repositionAround(zCtx2Menu, menuWidth, menuHeight);
            if (appState.positionObserver) appState.positionObserver.disconnect();
            appState.positionObserver = new MutationObserver(() => repositionAround(zCtx2Menu, menuWidth, menuHeight));
            appState.positionObserver.observe(zCtx2Menu, { attributes: true, attributeFilter: ['style'] });
        } else {
            positionInitially(event.clientX, event.clientY, menuWidth, menuHeight);
        }
        requestAnimationFrame(() => {
            appState.menuElement.classList.add('visible');
            appState.isVisible = true;
        });
      }, 50);
    }
    function positionInitially(clientX, clientY, menuWidth, menuHeight) {
        const { innerWidth, innerHeight } = window;
        const padding = 5;
        let x = clientX;
        let y = clientY;
        if (x + menuWidth + padding > innerWidth) { x = innerWidth - menuWidth - padding; }
        if (y + menuHeight + padding > innerHeight) { y = clientY - menuHeight - padding; }
        x = Math.max(padding, x);
        y = Math.max(padding, y);
        appState.menuElement.style.left = `${x}px`;
        appState.menuElement.style.top = `${y}px`;
    }
    function repositionAround(anchorElement, menuWidth, menuHeight) {
        const anchorRect = anchorElement.getBoundingClientRect();
        if (anchorRect.width === 0) return;
        let newTop, newLeft;
        newLeft = anchorRect.left + (anchorRect.width / 2) - (menuWidth / 2);
        if (anchorRect.top > (menuHeight + 20)) {
            newTop = anchorRect.top - menuHeight - 8;
        } else {
            newTop = anchorRect.bottom + 8;
        }
        const padding = 10;
        newLeft = Math.max(padding, Math.min(newLeft, window.innerWidth - menuWidth - padding));
        newTop = Math.max(padding, Math.min(newTop, window.innerHeight - menuHeight - padding));
        appState.menuElement.style.left = `${newLeft}px`;
        appState.menuElement.style.top = `${newTop}px`;
    }
    function bindEvents() {
        appState.dom.home.onclick = () => { window.location.href = window.location.origin; hideMenu(); };
        appState.dom.back.onclick = () => { window.history.back(); hideMenu(); };
        appState.dom.forward.onclick = () => { window.history.forward(); hideMenu(); };
        appState.dom.reload.onclick = () => { window.location.reload(); hideMenu(); };
        appState.dom.trash.onclick = deepDeleteElement;
        document.addEventListener('contextmenu', onContextMenu, true);
        document.addEventListener('mousedown', (e) => {
            if (appState.isVisible && e.button === 0 && appState.menuElement && !e.composedPath().includes(appState.menuElement)) {
                hideMenu();
            }
        }, true);
        window.addEventListener('scroll', hideMenu, { passive: true, capture: true });
        window.addEventListener('resize', hideMenu);
        window.addEventListener('blur', hideMenu);
    }
    function initialize() {
      if (!document.body) { setTimeout(initialize, 50); return; }
      createView();
      bindEvents();
    }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initialize);
    } else {
      initialize();
    }
  })();
}
''';









const zContextMenu2 =
'''
if (typeof window.ZTaskManager === 'undefined') {
    const STORE_NAME = 'zContextMenu2State';
    const HISTORY_KEY = 'promptHistory';

    window.ZTaskManager = {
        promptHistory: [],
        currentTaskId: 1,
        timerIntervals: new Map(),
        subscribers: [],

        async loadState() {
            if (!window.ZSharedDB) return;
try {
                const state = await window.ZSharedDB.performTransaction(STORE_NAME, 'readonly', store => store.get(HISTORY_KEY));
                if (state && Array.isArray(state.history)) { this.promptHistory = state.history; }
            } catch(e) { console.error("ZTaskManager: Failed to load state.", e); }
        },
        async saveState() {
            if (!window.ZSharedDB) return;
            try {
                await window.ZSharedDB.performTransaction(STORE_NAME, 'readwrite', store =>
                    store.put({ id: HISTORY_KEY, history: this.promptHistory })
                );
            } catch(e) { console.error("ZTaskManager: Failed to save state.", e); }
        },
        subscribe(callback) { this.subscribers.push(callback); return () => { this.subscribers = this.subscribers.filter(sub => sub !== callback); }; },
        notify() { this.subscribers.forEach(callback => callback()); },
        clearPromptHistory() { this.promptHistory = []; this.saveState(); this.notify(); },
        updateHistory(text) {
            let prompt = this.promptHistory.find(p => p.text === text);
            if (prompt) {
                this.promptHistory = this.promptHistory.filter(p => p.text !== text);
                prompt.clickCount = (prompt.clickCount || 1) + 1;
            } else {
                prompt = { text: text, clickCount: 1 };
            }
            this.promptHistory.unshift(prompt);
            if (this.promptHistory.length > 20) this.promptHistory.pop();
            this.saveState();
            this.notify();
        },
        addPromptToHistory(text) { if (text) { this.updateHistory(text); } },
        addTask(mediaData, userPrompt, fullPrompt) {
            this.addPromptToHistory(userPrompt);
            const newTask = { id: this.currentTaskId++, status: 'sent', text: fullPrompt, mediaData: mediaData, mediaUrl: null, startTime: Date.now() };
            this.notify();
            return newTask;
        }
    };
    async function initTaskManager() {
        await window.ZTaskManager.loadState();
        if (typeof window.ZContextMenu2InitializeCallback === 'function') { window.ZContextMenu2InitializeCallback(); }
    }
    if (window.ZDB_READY) { initTaskManager(); } else { document.addEventListener('ZDB_READY', initTaskManager, { once: true }); }
}

if (typeof window.ZContextMenu2Initialized === 'undefined') {
  window.ZContextMenu2Initialized = true;
  (function() {
    const SYSTEM_PROMPT = "Keep everything (scene, style, charactor, hair, face, mood, body rate, pose, action, animation,...), zoom out if limit body rate, just edit: ";
    const LAZY_ATTRIBUTES = ['data-src', 'data-lazy-src', 'data-original', 'data-url', 'data-srcset'];
    const PLACEHOLDER_KEYWORDS = ['lazy_placeholder', 'placeholder.gif', '1x1.gif', 'blank.gif', 'data:image/gif;base64'];
    const CORS_PROXY_URL = 'https://images.weserv.nl/?url=';

    const appState = {
      shadowHost: null, menuElement: null, isVisible: false, dom: {}, capturedMedia: null,
      promptScrollIndex: 0, MAX_PROMPT_DISPLAY: 5,
      unsubscribe: null, lastMousePos: { x: 0, y: 0 }
    };
    const ICONS = {
      send: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>`,
      close: `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>`,
      arrowLeft: `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>`,
      arrowRight: `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>`,
      trash: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>`,
      latest: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"></path></svg>`
    };
    let policy = window.trustedTypes?.createPolicy('z-context-menu2-policy', { createHTML: string => string });
    const setHTML = (element, html) => { if (policy) element.innerHTML = policy.createHTML(html); else element.innerHTML = html; };

    async function handleSend(autoClose = false) {
        const userPrompt = appState.dom.input.value.trim();
        const fullPrompt = userPrompt ? SYSTEM_PROMPT + userPrompt : "";
        if (appState.capturedMedia || userPrompt) {
            const mediaToSend = appState.capturedMedia;
            if (userPrompt) { window.ZTaskManager.addPromptToHistory(userPrompt); }
            if (mediaToSend || userPrompt) {
                 const newTask = window.ZTaskManager.addTask(mediaToSend, userPrompt, fullPrompt);
                 const payload = { type: 'ZContextMenu2Send', data: { taskId: newTask.id, text: fullPrompt, mediaData: mediaToSend } };
                 window.chrome.webview.postMessage(JSON.stringify(payload));
            }
            appState.dom.input.value = '';
            appState.capturedMedia = null;
            renderMediaPreview();
            hideMenu();
        }
    }
    async function handleTagClick(promptText) {
        appState.dom.input.value = promptText;
        await handleSend(true);
    }
    function isPlaceholder(url) {
        if (!url || typeof url !== 'string') return true;
        if (url.length < 50 && url.startsWith('data:')) return true;
        return PLACEHOLDER_KEYWORDS.some(keyword => url.includes(keyword));
    }
    function findBestUrl(mediaElement) {
        let bestUrl = mediaElement.currentSrc || mediaElement.src;
        for (const attr of LAZY_ATTRIBUTES) {
            if (mediaElement.hasAttribute(attr)) {
                const lazyUrl = mediaElement.getAttribute(attr);
                if (lazyUrl && !isPlaceholder(lazyUrl)) { bestUrl = lazyUrl; break; }
            }
        }
        if (mediaElement.srcset) {
             const sources = mediaElement.srcset.split(',').map(s => s.trim().split(' ')[0]);
             const srcsetUrl = sources[sources.length - 1];
             if(srcsetUrl && !isPlaceholder(srcsetUrl)) { bestUrl = srcsetUrl; }
        }
        if (bestUrl && !bestUrl.startsWith('data:') && !bestUrl.startsWith('http')) {
             try { bestUrl = new URL(bestUrl, window.location.href).href; } catch(e) {}
        }
        return isPlaceholder(bestUrl) ? null : bestUrl;
    }

    function createView() {
      if (appState.shadowHost) return;
      if (!document.body) { setTimeout(createView, 50); return; }
      appState.shadowHost = document.createElement('div');
      appState.shadowHost.id = 'z-context-menu2-host';
      Object.assign(appState.shadowHost.style, { position: 'fixed', top: '0', left: '0', width: '100%', height: '100%', pointerEvents: 'none', zIndex: '2147483647', display: 'none' });
      document.body.appendChild(appState.shadowHost);
      const shadowRoot = appState.shadowHost.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent = `
        :host { --bg-color: rgba(28, 28, 28, 0.9); --blur: 16px; --text-color: #e0e0e0; --hover-bg-color: rgba(255, 255, 255, 0.1); --input-bg-color: rgba(255, 255, 255, 0.05); --radius: 24px; --btn-size: 36px; --delete-color: #ef4444; }
        .menu-container { position: fixed; z-index: 1; background-color: var(--bg-color); backdrop-filter: blur(var(--blur)) saturate(1.2); -webkit-backdrop-filter: blur(var(--blur)) saturate(1.2); border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 4px 15px rgba(0,0,0,0.3); border-radius: var(--radius); padding: 6px; user-select: none; display: flex; flex-direction: column; gap: 6px; opacity: 0; transform: scale(0.95); transition: opacity 0.15s ease, transform 0.15s ease; min-width: 320px; pointer-events: all; }
        .menu-container.visible { opacity: 1; transform: scale(1); }
        .media-preview { position: relative; display: none; flex-shrink: 0; }
        .media-preview img { width: var(--btn-size); height: var(--btn-size); border-radius: 8px; object-fit: cover; }
        .remove-media-btn { position: absolute; top: -5px; right: -5px; width: 16px; height: 16px; background-color: #333; color: white; border: 1px solid #555; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; transition: all 0.2s; }
        .remove-media-btn:hover { background-color: #ff4d4d; transform: scale(1.1); }
        .menu-btn { width: var(--btn-size); height: var(--btn-size); display: flex; align-items: center; justify-content: center; border-radius: 50%; color: var(--text-color); cursor: pointer; transition: all 0.15s ease; border: none; background: transparent; padding: 0; flex-shrink: 0; }
        .menu-btn:hover { transform: scale(1.1); background-color: var(--hover-bg-color); }
        .menu-btn:active { transform: scale(0.95); }
        #z-ctx2-chat-input { flex-grow: 1; background: var(--input-bg-color); border: none; outline: none; color: var(--text-color); padding: 8px 12px; border-radius: 18px; font-size: 14px; font-family: inherit; resize: none; }
        .input-bar { display: flex; align-items: center; gap: 6px; width: 100%; }
        .prompt-history-bar { display: none; align-items: center; gap: 4px; padding-bottom: 6px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }
        .prompt-history-container { display: flex; gap: 8px; overflow: hidden; flex-grow: 1; }
        .nav-btn { width: 24px; height: 24px; }
        .nav-btn.disabled { opacity: 0.3; pointer-events: none; }
        .small-btn { width: 20px; height: 20px; }
        .small-btn svg { width: 12px; height: 12px; }
        .prompt-tag { background-color: var(--input-bg-color); color: #ccc; font-size: 12px; padding: 4px 8px; border-radius: 12px; cursor: pointer; white-space: nowrap; border: 1px solid rgba(255, 255, 255, 0.1); transition: all 0.2s ease; user-select: none; display: inline-flex; align-items: center; }
        .prompt-tag:hover { border-color: #00BFFF; box-shadow: 0 0 5px rgba(0, 191, 255, 0.5); color: #fff; }
        .prompt-tag.latest { background-color: #00aeff; color: white; border-color: #00BFFF; }
        .prompt-tag.top-rank { opacity: 0.8; }
        .clear-history-btn:hover { color: var(--delete-color); }
      `;
      shadowRoot.appendChild(style);
      appState.menuElement = document.createElement('div');
      appState.menuElement.className = 'menu-container';
      setHTML(appState.menuElement, `
        <div class="prompt-history-bar">
            <button class="menu-btn nav-btn" id="prompt-nav-prev">${ICONS.arrowLeft}</button>
            <div class="prompt-history-container"></div>
            <button class="menu-btn nav-btn" id="prompt-nav-next">${ICONS.arrowRight}</button>
            <button class="menu-btn clear-history-btn small-btn" title="Clear History">${ICONS.trash}</button>
        </div>
        <div class="input-bar">
            <div class="media-preview"></div>
            <textarea id="z-ctx2-chat-input" rows="1" placeholder="Type a message..."></textarea>
            <button class="menu-btn" id="z-ctx2-send-btn" title="Send">${ICONS.send}</button>
        </div>
      `);
      shadowRoot.append(appState.menuElement);
      appState.dom = {
        input: shadowRoot.getElementById('z-ctx2-chat-input'),
        sendBtn: shadowRoot.getElementById('z-ctx2-send-btn'),
        mediaPreview: shadowRoot.querySelector('.media-preview'),
        promptHistoryBar: shadowRoot.querySelector('.prompt-history-bar'),
        promptHistoryContainer: shadowRoot.querySelector('.prompt-history-container'),
        promptNavPrev: shadowRoot.getElementById('prompt-nav-prev'),
        promptNavNext: shadowRoot.getElementById('prompt-nav-next'),
        clearHistoryBtn: shadowRoot.querySelector('.clear-history-btn'),
      };
    }
    function renderPromptHistory() {
        if (!window.ZTaskManager || !appState.dom.promptHistoryContainer) return;
        const container = appState.dom.promptHistoryContainer;
        setHTML(container, '');
        const allHistory = window.ZTaskManager.promptHistory;
        appState.dom.promptHistoryBar.style.display = allHistory.length > 0 ? 'flex' : 'none';
        if (allHistory.length === 0) return;
        const itemsToShow = allHistory.slice(appState.promptScrollIndex, appState.promptScrollIndex + appState.MAX_PROMPT_DISPLAY);
        itemsToShow.forEach((item, index) => {
            const tag = document.createElement('div');
            const isLatest = (appState.promptScrollIndex + index) === 0;
            tag.className = `prompt-tag ${isLatest ? 'latest' : 'top-rank'}`;
            const shortText = item.text.length > 20 ? item.text.substring(0, 20) + '…' : item.text;
            tag.textContent = shortText;
            tag.title = `${item.text} (${item.clickCount} uses)`;
            tag.onclick = (e) => { e.stopPropagation(); handleTagClick(item.text); };
            container.appendChild(tag);
        });
        const maxScroll = Math.max(0, allHistory.length - appState.MAX_PROMPT_DISPLAY);
        appState.dom.promptNavPrev.classList.toggle('disabled', appState.promptScrollIndex === 0);
        appState.dom.promptNavNext.classList.toggle('disabled', appState.promptScrollIndex >= maxScroll);
    }
    function handlePromptNav(direction) {
        if (!window.ZTaskManager) return;
        const allHistory = window.ZTaskManager.promptHistory;
        const maxScroll = Math.max(0, allHistory.length - appState.MAX_PROMPT_DISPLAY);
        let newIndex = appState.promptScrollIndex + (direction === 'next' ? 1 : -1);
        newIndex = Math.max(0, Math.min(newIndex, maxScroll));
        if (newIndex !== appState.promptScrollIndex) { appState.promptScrollIndex = newIndex; renderPromptHistory(); }
    }
    function hideMenu() {
      if (!appState.isVisible) return;
      if (appState.unsubscribe) { appState.unsubscribe(); appState.unsubscribe = null; }
      if(appState.menuElement) {
        appState.menuElement.classList.remove('visible');
        setTimeout(() => { if (!appState.isVisible && appState.shadowHost) { appState.shadowHost.style.display = 'none'; } }, 150);
      }
      appState.isVisible = false;
      appState.capturedMedia = null;
    }
    async function onContextMenu(event) {
        if (!document.body || !window.ZTaskManager) return;
        event.preventDefault(); event.stopPropagation();
        createView();
        if (appState.menuElement && event.composedPath().includes(appState.menuElement)) return;
        if (appState.isVisible) hideMenu();
        appState.capturedMedia = null;
        const target = findBestMediaElement(event.target, event.clientX, event.clientY);
        if (target) { await captureMedia(target); }
        showMenuAt(event.clientX, event.clientY);
    }
    function showMenuAt(clientX, clientY) {
        if (!window.ZTaskManager || !appState.menuElement || !appState.shadowHost) return;
        if (!appState.unsubscribe) { appState.unsubscribe = window.ZTaskManager.subscribe(renderPromptHistory); }
        appState.dom.input.value = '';
        renderMediaPreview();
        renderPromptHistory();
        appState.shadowHost.style.display = 'block';
        appState.menuElement.style.left = '-9999px';
        appState.menuElement.style.top = '-9999px';
        appState.menuElement.classList.add('visible');
        requestAnimationFrame(() => {
            const { offsetWidth: menuWidth, offsetHeight: menuHeight } = appState.menuElement;
            const { innerWidth, innerHeight } = window;
            let x = clientX, y = clientY;
            if (x + menuWidth > innerWidth - 10) x = innerWidth - menuWidth - 10;
            if (y + menuHeight > innerHeight - 10) y = clientY - menuHeight - 10;
            if (x < 10) x = 10; if (y < 10) y = 10;
            appState.menuElement.style.left = `${x}px`;
            appState.menuElement.style.top = `${y}px`;
            appState.isVisible = true;
            appState.dom.input.focus();
        });
    }
    function findBestMediaElement(initialTarget, mouseX, mouseY) {
        let currentElement = initialTarget;
        for (let i = 0; i < 3 && currentElement && currentElement.tagName !== 'BODY'; i++) {
            const tagName = currentElement.tagName;
            if (tagName === 'VIDEO' || tagName === 'IMG') {
                const rect = currentElement.getBoundingClientRect();
                if (rect.width > 30 && rect.height > 30) return currentElement;
            }
            currentElement = currentElement.parentElement;
        }
        const allMedia = Array.from(document.querySelectorAll('video, img'));
        const visibleMedia = allMedia.filter(m => {
            const rect = m.getBoundingClientRect();
            return rect.width > 30 && rect.height > 30 && rect.top < window.innerHeight && rect.bottom > 0 && rect.left < window.innerWidth && rect.right > 0;
        });
        if (visibleMedia.length === 0) return null;
        visibleMedia.sort((a, b) => {
            const rectA = a.getBoundingClientRect(); const rectB = b.getBoundingClientRect();
            const distA = Math.hypot(rectA.left + rectA.width / 2 - mouseX, rectA.top + rectA.height / 2 - mouseY);
            const distB = Math.hypot(rectB.left + rectB.width / 2 - mouseX, rectB.top + rectB.height / 2 - mouseY);
            return distA - distB;
        });
        return visibleMedia[0] || null;
    }

    // ==============================================================================
    // GIẢI PHÁP XỬ LÝ CORS THÔNG MINH
    // ==============================================================================
    async function getUntaintedMedia(mediaSource, isVideo) {
        return new Promise((resolve, reject) => {
            const tempMedia = isVideo ? document.createElement('video') : new Image();
            tempMedia.crossOrigin = 'anonymous';

            const success = () => {
                // For video, we need to wait for data to be loaded
                if (isVideo && tempMedia.readyState < 2) return;

                // Cleanup listeners
                tempMedia.onload = null;
                tempMedia.onloadeddata = null;
                tempMedia.onerror = null;
                resolve(tempMedia);
            };

            const failure = (err) => {
                tempMedia.onload = null;
                tempMedia.onloadeddata = null;
                tempMedia.onerror = null;
                reject(new Error(`Failed to load media source. ${err?.type || ''}`));
            };

            tempMedia.onload = success;
            if (isVideo) {
                tempMedia.onloadeddata = success;
            }
            tempMedia.onerror = failure;

            tempMedia.src = mediaSource;
            if (isVideo) {
                 tempMedia.load(); // Important for some browsers
            }
        });
    }

    async function captureMedia(mediaElement) {
        const sourceUrl = findBestUrl(mediaElement);
        if (!sourceUrl) { appState.capturedMedia = null; return; }

        const isVideo = mediaElement.tagName === 'VIDEO';
        let mediaToDraw = isVideo ? mediaElement : null;

        try {
            if (!isVideo) {
                // Strategy 1: Attempt to load the image with crossOrigin attribute
                mediaToDraw = await getUntaintedMedia(sourceUrl, false);
                (window._zOriginalConsole || console).log('Success: Loaded untainted image directly.');
            }
        } catch (e) {
            (window._zOriginalConsole || console).warn(`Direct untainted load failed. Falling back to CORS proxy. Reason: ${e.message}`);
            // Strategy 2: Fallback to a CORS proxy for images that fail direct load
            try {
                const proxiedUrl = `${CORS_PROXY_URL}${encodeURIComponent(sourceUrl)}`;
                mediaToDraw = await getUntaintedMedia(proxiedUrl, false);
                (window._zOriginalConsole || console).log('Success: Loaded image via CORS proxy.');
            } catch (proxyError) {
                 (window._zOriginalConsole || console).error(`Fatal: Both direct and proxy load failed. Reason: ${proxyError.message}`);
                 appState.capturedMedia = null;
                 return;
            }
        }

        // At this point, mediaToDraw should be a valid, untainted source
        try {
            const mediaWidth = isVideo ? mediaElement.videoWidth : mediaToDraw.naturalWidth;
            const mediaHeight = isVideo ? mediaElement.videoHeight : mediaToDraw.naturalHeight;

            if (!mediaWidth || !mediaHeight) throw new Error("Media has no dimensions.");

            const canvas = document.createElement('canvas');
            canvas.width = mediaWidth;
            canvas.height = mediaHeight;
            const ctx = canvas.getContext('2d');

            // For video, draw the original element to get the current frame
            ctx.drawImage(isVideo ? mediaElement : mediaToDraw, 0, 0, canvas.width, canvas.height);

            const dataUrl = canvas.toDataURL('image/jpeg', 0.9);
            if (dataUrl.length < 100) throw new Error("Canvas generated empty data.");

            appState.capturedMedia = { type: 'base64', data: dataUrl, sourceUrl: sourceUrl };
        } catch(canvasError) {
             (window._zOriginalConsole || console).error(`Canvas drawing failed unexpectedly. Reason: ${canvasError.message}`);
             appState.capturedMedia = null;
        }
    }

    function renderMediaPreview() {
        if (!appState.dom.mediaPreview) return;
        const previewContainer = appState.dom.mediaPreview;
        if (appState.capturedMedia && appState.capturedMedia.data) {
            const displayUrl = appState.capturedMedia.data;
            previewContainer.className = 'media-preview';
            setHTML(previewContainer, `<img src="${displayUrl}" alt="Captured media"><div class="remove-media-btn" title="Remove Media">${ICONS.close}</div>`);
            previewContainer.style.display = 'block';
            previewContainer.querySelector('.remove-media-btn').onmousedown = (event) => { event.stopPropagation(); appState.capturedMedia = null; renderMediaPreview(); };
        } else {
            previewContainer.style.display = 'none';
            setHTML(previewContainer, '');
        }
    }

    function bindGlobalEvents() {
        document.addEventListener('contextmenu', onContextMenu, true);
        document.addEventListener('mousedown', (e) => { if (e.button === 0 && appState.isVisible && appState.shadowHost && !e.composedPath().includes(appState.shadowHost)) { hideMenu(); } }, true);
        document.addEventListener('mousemove', e => { appState.lastMousePos.x = e.clientX; appState.lastMousePos.y = e.clientY; }, { capture: true, passive: true });
        window.addEventListener('scroll', hideMenu, { passive: true, capture: true });
        window.addEventListener('resize', hideMenu, { passive: true });
        window.addEventListener('blur', hideMenu, { passive: true });
    }
    function bindDynamicEvents() {
        if (!appState.dom.input) return;
        appState.dom.sendBtn.onclick = () => handleSend(true);
        appState.dom.input.onkeydown = (e) => { e.stopPropagation(); if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(true); } };
        appState.dom.promptNavPrev.onclick = () => handlePromptNav('prev');
        appState.dom.promptNavNext.onclick = () => handlePromptNav('next');
        appState.dom.clearHistoryBtn.onclick = () => window.ZTaskManager.clearPromptHistory();
    }
    function initialize() {
      // Sửa lỗi console.warn
      if (!window._zOriginalConsole) { window._zOriginalConsole = { log: console.log, warn: console.warn, error: console.error }; }
      createView();
      bindDynamicEvents();
      bindGlobalEvents();
      renderPromptHistory();
      window.ZContextMenu2Instance = { handleTagClick: handleTagClick };
    }
    window.ZContextMenu2InitializeCallback = function() {
        if (document.body) { initialize(); } else { document.addEventListener('DOMContentLoaded', initialize); }
    };
    if (window.ZDB_READY && window.ZTaskManager && window.ZTaskManager.loadState) {
        window.ZContextMenu2InitializeCallback();
    }
  })();
}
''';









const zMediaPopup =
'''
if (typeof window.ZMediaPopupInitialized !== 'undefined') {
    if (window.ZMediaPopupTeardown) window.ZMediaPopupTeardown();
}
window.ZMediaPopupInitialized = true;

(function() {
    const STORE_NAME = 'zMediaPopupState';
    const STATE_KEY = 'lastState';
    const MIN_WIDTH_THRESHOLD = 300;
    const MIN_HEIGHT_THRESHOLD = 200;
    const TARGET_SCAN_INTERVAL = 500;
    const INACTIVITY_TIMEOUT = 3000;
    const TOP_PADDING = 10;
    const DRAG_THRESHOLD = 5;

    const appState = {
        dom: {},
        targetMedia: null,
        isScrubbing: false,
        isViewInitialized: false,
        playbackSpeeds: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 4, 8, 16],
        settings: {
            currentSpeedIndex: 3,
            position: null
        },
        speedChangeTimeout: null,
        trackingInterval: null,
        isPanelVisible: false,
        inactivityTimer: null,
        isDragging: false,
        dragStart: { x: 0, y: 0, startX: 0, startY: 0 },
        isPositionFixed: false
    };

    let isBlockingClick = false;

    const ICONS = {
        play: `<svg class="play-icon" viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>`,
        pause: `<svg class="pause-icon" viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>`,
        skip: `<svg viewBox="0 0 24 24"><polygon points="5 4 15 12 5 20 5 4"></polygon><line x1="19" y1="5" x2="19" y2="19"></line></svg>`
    };

    let policy;
    try { policy = window.trustedTypes.createPolicy('zmediaPolicy', { createHTML: input => input }); } catch(e) { policy = null; }
    const setHTML = (element, html) => { if (policy) element.innerHTML = policy.createHTML(html); else element.innerHTML = html; };

    const Persistence = {
        async performTransaction(mode, action) {
            if (!window.ZSharedDB || typeof window.ZSharedDB.performTransaction !== 'function') {
                return Promise.reject(new Error("ZMediaPopup Error: ZSharedDB core is not available."));
            }
            return window.ZSharedDB.performTransaction(STORE_NAME, mode, action);
        },
        async saveState() {
            try {
                await this.performTransaction('readwrite', store => store.put({ id: STATE_KEY, ...appState.settings }));
            } catch(e) {}
        },
        async loadState() {
            try {
                const savedState = await this.performTransaction('readonly', store => store.get(STATE_KEY));
                if (savedState) {
                    appState.settings = { ...appState.settings, ...savedState };
                    appState.isPositionFixed = !!appState.settings.position;
                    if (appState.settings.currentSpeedIndex >= appState.playbackSpeeds.length) {
                         appState.settings.currentSpeedIndex = 3;
                    }
                }
            } catch (e) {}
        }
    };

    function setTargetMedia(newMedia) {
        if (appState.targetMedia === newMedia) return;
        if (appState.targetMedia) {
            ['timeupdate', 'playing', 'pause', 'ended', 'durationchange', 'ratechange'].forEach(event => {
                appState.targetMedia.removeEventListener(event, updateMediaControlsUI);
            });
        }
        appState.targetMedia = newMedia;

        if (appState.targetMedia) {
            appState.targetMedia.playbackRate = appState.playbackSpeeds[appState.settings.currentSpeedIndex];
            ['timeupdate', 'playing', 'pause', 'ended', 'durationchange', 'ratechange'].forEach(event => {
                appState.targetMedia.addEventListener(event, updateMediaControlsUI);
            });
        }
        updateMediaControlsUI();
    }

    function togglePlayPause() {
        if (isBlockingClick) return;
        if (!appState.targetMedia) return;
        if (appState.targetMedia.paused) {
            appState.targetMedia.play().catch(e => console.error("Media play error:", e));
        } else {
            appState.targetMedia.pause();
        }
    }

    function changePlaybackSpeed(direction) {
        let newIndex = appState.settings.currentSpeedIndex;
        if (direction === 'next') {
            newIndex = (newIndex + 1) % appState.playbackSpeeds.length;
        } else if (direction === 'prev') {
            newIndex = (newIndex - 1 + appState.playbackSpeeds.length) % appState.playbackSpeeds.length;
        } else if (direction === 'reset') {
            newIndex = appState.playbackSpeeds.indexOf(1);
        }
        if (newIndex !== appState.settings.currentSpeedIndex) {
            setPlaybackSpeed(newIndex);
        }
    }

    function setPlaybackSpeed(newIndex) {
        appState.settings.currentSpeedIndex = newIndex;
        const newSpeed = appState.playbackSpeeds[appState.settings.currentSpeedIndex];
        appState.dom.speedBtn.classList.add('speed-pulse');
        setTimeout(() => appState.dom.speedBtn.classList.remove('speed-pulse'), 200);
        updateMediaControlsUI();
        clearTimeout(appState.speedChangeTimeout);
        appState.speedChangeTimeout = setTimeout(() => {
            if (appState.targetMedia) appState.targetMedia.playbackRate = newSpeed;
            Persistence.saveState();
        }, 500);
    }

    function handleSpeedClick(e) {
        if (isBlockingClick) return;
        e.preventDefault();
        e.stopPropagation();
        if (e.button === 1 || e.button === 2) {
            changePlaybackSpeed('reset');
        } else {
            changePlaybackSpeed('next');
        }
    }

    function handleSpeedWheel(e) {
        e.preventDefault();
        e.stopPropagation();
        if (e.deltaY < 0) {
            changePlaybackSpeed('prev');
        } else if (e.deltaY > 0) {
            changePlaybackSpeed('next');
        }
    }

    function handleSkipToEnd() {
        if (isBlockingClick) return;
        if (!appState.targetMedia || !isFinite(appState.targetMedia.duration)) return;
        appState.targetMedia.currentTime = appState.targetMedia.duration;
        appState.targetMedia.pause();
    }

    function handleProgressInteractionStart(e) {
        if (!appState.targetMedia || !isFinite(appState.targetMedia.duration)) return;
        appState.isScrubbing = true;
        document.addEventListener('mousemove', handleScrubbing);
        document.addEventListener('mouseup', handleProgressInteractionEnd, { once: true });
        handleScrubbing(e);
    }

    function handleScrubbing(e) {
        if (!appState.isScrubbing || !appState.targetMedia || !isFinite(appState.targetMedia.duration)) return;
        const rect = appState.dom.progressHitbox.getBoundingClientRect();
        const position = (e.clientX - rect.left) / rect.width;
        const percentage = Math.max(0, Math.min(100, position * 100));
        appState.dom.progressBar.value = percentage;
        appState.dom.progressBar.style.setProperty('--progress-width', `${percentage}%`);
        setHTML(appState.dom.percentLabel, `${percentage.toFixed(0)}%`);
        const newTime = (percentage / 100) * appState.targetMedia.duration;
        if (isFinite(newTime)) appState.targetMedia.currentTime = newTime;
    }

    function handleProgressInteractionEnd() {
        if (!appState.isScrubbing) return;
        appState.isScrubbing = false;
        document.removeEventListener('mousemove', handleScrubbing);
    }

    function handleProgressWheel(e) {
        if (!appState.targetMedia || !isFinite(appState.targetMedia.duration)) return;
        e.preventDefault();
        e.stopPropagation();
        const timeChange = e.deltaY > 0 ? 1 : -1;
        const newTime = appState.targetMedia.currentTime + timeChange;
        appState.targetMedia.currentTime = Math.max(0, Math.min(appState.targetMedia.duration, newTime));
    }

    function updateMediaControlsUI() {
        if (!appState.isViewInitialized) return;
        const media = appState.targetMedia;
        const hasMedia = media && isFinite(media.duration) && media.duration > 0;
        const { dom } = appState;
        dom.panelContainer.dataset.hasMedia = hasMedia;
        dom.panelContainer.dataset.paused = hasMedia ? media.paused : true;
        if (hasMedia) {
            if (!appState.isScrubbing) {
                const percentage = (media.currentTime / media.duration) * 100;
                dom.progressBar.value = percentage;
                dom.progressBar.style.setProperty('--progress-width', `${percentage}%`);
                setHTML(dom.percentLabel, `${percentage.toFixed(0)}%`);
            }
        } else {
            dom.progressBar.value = 0;
            dom.progressBar.style.setProperty('--progress-width', '0%');
            setHTML(dom.percentLabel, `0%`);
        }
        const currentSpeed = appState.playbackSpeeds[appState.settings.currentSpeedIndex];
        setHTML(dom.speedBtn, `${currentSpeed}x`);
    }

    function applyPosition(useTransition = false) {
        const panel = appState.dom.panelContainer;
        if (!panel) return;

        if (appState.isPositionFixed && appState.settings.position) {
            panel.style.left = appState.settings.position.left;
            panel.style.top = appState.settings.position.top;
        }

        const rect = panel.getBoundingClientRect();
        const padding = 10;
        let newLeft = rect.left;
        let newTop = rect.top;

        if (rect.right > window.innerWidth - padding) newLeft = window.innerWidth - rect.width - padding;
        if (rect.left < padding) newLeft = padding;
        if (rect.bottom > window.innerHeight - padding) newTop = window.innerHeight - rect.height - padding;
        if (rect.top < padding) newTop = padding;

        if (newLeft !== rect.left || newTop !== rect.top) {
            panel.style.transition = useTransition ? 'left 0.3s ease, top 0.3s ease' : 'none';
            panel.style.left = `${newLeft}px`;
            panel.style.top = `${newTop}px`;
            if(useTransition) {
                setTimeout(() => { panel.style.transition = 'opacity 0.4s ease'; }, 300);
            } else {
                 panel.style.transition = 'opacity 0.4s ease';
            }
        }
    }

    function resetInactivityTimer() {
        clearTimeout(appState.inactivityTimer);
        if (appState.dom.panelContainer) appState.dom.panelContainer.classList.add('active');
        appState.inactivityTimer = setTimeout(() => {
            if (appState.dom.panelContainer) appState.dom.panelContainer.classList.remove('active');
        }, INACTIVITY_TIMEOUT);
    }

    function findTargetMediaElement() {
        const fullscreenElement = document.fullscreenElement || document.webkitFullscreenElement;
        if (fullscreenElement) {
            const mediaInFs = fullscreenElement.querySelector('video') || fullscreenElement.querySelector('audio');
            if (mediaInFs) return mediaInFs;
            if (['VIDEO', 'AUDIO'].includes(fullscreenElement.tagName)) return fullscreenElement;
        }
        const mediaElements = Array.from(document.querySelectorAll('video, audio'));
        if (mediaElements.length === 0) return null;

        const visibleAndValidMedia = mediaElements.filter(m => {
            const rect = m.getBoundingClientRect();
            return rect.width > MIN_WIDTH_THRESHOLD && rect.height > MIN_HEIGHT_THRESHOLD &&
                   rect.top < window.innerHeight && rect.bottom > 0 &&
                   rect.left < window.innerWidth && rect.right > 0 &&
                   !isNaN(m.duration) && isFinite(m.duration) && m.duration > 0;
        });
        if (visibleAndValidMedia.length === 0) return null;

        visibleAndValidMedia.sort((a, b) => {
            const aPlaying = !a.paused;
            const bPlaying = !b.paused;
            if (aPlaying !== bPlaying) return aPlaying ? -1 : 1;
            return (b.offsetWidth * b.offsetHeight) - (a.offsetWidth * a.offsetHeight);
        });
        return visibleAndValidMedia[0];
    }

    // ==============================================================================
    // LOGIC ĐÃ SỬA LỖI
    // ==============================================================================
    function trackMediaPosition() {
        if (appState.isDragging) return;
        const newMedia = findTargetMediaElement();
        setTargetMedia(newMedia);

        const panel = appState.dom.panelContainer;
        if (!panel) return;

        if (!appState.targetMedia) {
            if (appState.isPanelVisible) {
                panel.classList.remove('visible');
                appState.isPanelVisible = false;
            }
            return;
        }

        const mediaRect = appState.targetMedia.getBoundingClientRect();

        // **ĐIỂM SỬA LỖI QUAN TRỌNG NHẤT**
        // Nếu vị trí đã được cố định, KHÔNG tính toán lại vị trí tự động.
        // Chỉ cần đảm bảo panel nằm trong màn hình.
        if (appState.isPositionFixed) {
            applyPosition();
        } else {
            // Logic tính toán vị trí tự động chỉ chạy khi không bị ghim.
            const panelWidth = panel.offsetWidth || 320;
            const newLeft = mediaRect.left + (mediaRect.width / 2) - (panelWidth / 2);
            const newTop = mediaRect.top + TOP_PADDING;
            const padding = 10;
            panel.style.left = `${Math.max(padding, Math.min(newLeft, window.innerWidth - panelWidth - padding))}px`;
            panel.style.top = `${Math.max(padding, Math.min(newTop, window.innerHeight - panel.offsetHeight - padding))}px`;
        }

        const isVisibleOnScreen = (mediaRect.bottom > 50 && mediaRect.top < (window.innerHeight - 50));
        if (isVisibleOnScreen && !appState.isPanelVisible) {
            panel.style.display = 'flex';
            requestAnimationFrame(() => {
                panel.classList.add('visible');
                appState.isPanelVisible = true;
                resetInactivityTimer();
            });
        } else if (!isVisibleOnScreen && appState.isPanelVisible) {
            panel.classList.remove('visible');
            appState.isPanelVisible = false;
        }
    }

    function handleDragStart(e) {
        if (e.target.closest('.progress-hitbox')) return;
        e.preventDefault();
        e.stopPropagation();

        appState.isDragging = true;
        appState.dragStart.startX = e.clientX;
        appState.dragStart.startY = e.clientY;

        const panel = appState.dom.panelContainer;
        const rect = panel.getBoundingClientRect();
        appState.dragStart.x = e.clientX - rect.left;
        appState.dragStart.y = e.clientY - rect.top;

        panel.style.transition = 'none';
        document.addEventListener('mousemove', handleDragMove);
        document.addEventListener('mouseup', handleDragEnd, { once: true });
    }

    function handleDragMove(e) {
        if (!appState.isDragging) return;
        const distance = Math.hypot(e.clientX - appState.dragStart.startX, e.clientY - appState.dragStart.startY);
        if (distance > DRAG_THRESHOLD) {
            isBlockingClick = true;
            const newLeft = e.clientX - appState.dragStart.x;
            const newTop = e.clientY - appState.dragStart.y;
            appState.dom.panelContainer.style.left = `${newLeft}px`;
            appState.dom.panelContainer.style.top = `${newTop}px`;
        }
    }

    function handleDragEnd(e) {
        if (!appState.isDragging) return;
        appState.isDragging = false;
        document.removeEventListener('mousemove', handleDragMove);
        const panel = appState.dom.panelContainer;
        const distance = Math.hypot(e.clientX - appState.dragStart.startX, e.clientY - appState.dragStart.startY);

        if (distance > DRAG_THRESHOLD) {
            const rect = panel.getBoundingClientRect();
            appState.settings.position = { left: `${rect.left}px`, top: `${rect.top}px` };
            appState.isPositionFixed = true;
            applyPosition(true);
            Persistence.saveState();
            setTimeout(() => { isBlockingClick = false; }, 150);
        } else {
            // **ĐIỂM SỬA LỖI THỨ HAI: LOGIC HỦY GHIM**
            // Nếu không phải là kéo (khoảng cách nhỏ) và panel đang được ghim,
            // và người dùng không click vào một nút cụ thể, thì hủy ghim.
            if (!isBlockingClick && appState.isPositionFixed) {
                if (!e.target.closest('.icon-btn, .speed-badge, .progress-hitbox')) {
                     appState.isPositionFixed = false;
                     appState.settings.position = null;
                     Persistence.saveState();
                     // Gọi lại trackMediaPosition để nó quay về chế độ tự động ngay lập tức.
                     trackMediaPosition();
                }
            }
            isBlockingClick = false;
        }

        panel.style.transition = 'opacity 0.4s ease';
    }

    const View = {
        create: function() {
            document.getElementById('z-media-shadow-host')?.remove();
            const shadowHost = document.createElement('div');
            shadowHost.id = 'z-media-shadow-host';
            Object.assign(shadowHost.style, { position: 'fixed', top: '0', left: '0', zIndex: '2147483647', pointerEvents: 'none', width: '1px', height: '1px' });
            document.body.appendChild(shadowHost);
            const shadowRoot = shadowHost.attachShadow({ mode: 'open' });
            const style = document.createElement('style');
            style.textContent = `
                :host { --bg-color: rgba(30, 30, 30, 0.75); --blur: 8px; --text-color: #e0e0e0; --highlight-color: #00aeff; --panel-width: 320px; --btn-size: 36px; --speed-btn-width: 50px; --progress-height: 6px; --thumb-size: 14px; --radius: 18px; --progress-bg: rgba(255, 255, 255, 0.4); --progress-thumb: #fff; }
                .panel-container { position: fixed; width: var(--panel-width); max-width: 80vw; opacity: 0; pointer-events: none; transition: opacity 0.4s ease; z-index: 2147483647; display: flex; }
                .panel-container.visible.active { opacity: 1; pointer-events: all; }
                .media-wrapper { display: flex; align-items: center; gap: 8px; background-color: var(--bg-color); padding: 5px 10px; border: 1px solid rgba(255, 255, 255, 0.1); box-shadow: 0 4px 8px rgba(0,0,0,0.3); border-radius: var(--radius); color: var(--text-color); font-size: 13px; user-select: none; width: 100%; cursor: grab; backdrop-filter: blur(var(--blur)); -webkit-backdrop-filter: blur(var(--blur)); }
                .media-wrapper:active { cursor: grabbing; }
                .panel-container[data-has-media="false"] .media-control { opacity: 0.6; pointer-events: none; }
                .play-pause-btn .play-icon, .play-pause-btn .pause-icon { display: none; }
                .panel-container[data-paused="true"] .play-pause-btn .play-icon { display: block; }
                .panel-container[data-paused="false"] .play-pause-btn .pause-icon { display: block; }
                .play-pause-btn { color: var(--highlight-color); }
                .icon-btn, .speed-badge { display: flex; justify-content: center; align-items: center; cursor: pointer; flex-shrink: 0; transition: all 0.15s ease; border: none; background: transparent; padding: 0; }
                .icon-btn { width: var(--btn-size); height: var(--btn-size); border-radius: 50%; color: var(--text-color); }
                .icon-btn:hover { background-color: rgba(255,255,255,0.1); }
                .speed-badge { width: var(--speed-btn-width); height: calc(var(--btn-size) * 0.8); border-radius: 8px; font-size: 12px; font-weight: 600; font-variant-numeric: tabular-nums; background-color: rgba(255,255,255,0.1); user-select: none; }
                .speed-badge:hover { transform: scale(1.05); background-color: rgba(255,255,255,0.2); }
                @keyframes speedPulse { 0% { transform: scale(1.1); } 100% { transform: scale(1); } }
                .speed-badge.speed-pulse { animation: speedPulse 0.2s ease-out; }
                .progress-bar-container { flex-grow: 1; height: 100%; display: flex; align-items: center; gap: 8px; }
                .progress-bar-wrapper { flex-grow: 1; position: relative; }
                .progress-hitbox { position: absolute; top: -10px; bottom: -10px; left: 0; right: 0; z-index: 3; cursor: ew-resize; }
                .percent-label { width: 35px; text-align: right; flex-shrink: 0; font-size: 12px; user-select: text; cursor: default; }
                .media-progress { -webkit-appearance: none; appearance: none; width: 100%; height: var(--progress-height); background-color: var(--progress-bg); border-radius: 3px; outline: none; margin: 0; pointer-events: none; }
                .media-progress::-webkit-slider-runnable-track { background: linear-gradient(to right, var(--highlight-color) var(--progress-width), transparent var(--progress-width)); height: var(--progress-height); border-radius: 3px; }
                .media-progress::-webkit-slider-thumb { -webkit-appearance: none; appearance: none; width: var(--thumb-size); height: var(--thumb-size); border-radius: 50%; background: var(--progress-thumb); margin-top: calc( (var(--progress-height) - var(--thumb-size)) / 2 ); }
                .icon-btn { width: var(--btn-size); height: var(--btn-size); }
                .icon-btn svg { width: 22px; height: 22px; stroke-width: 2.5; }
                .speed-badge { width: var(--speed-btn-width); height: calc(var(--btn-size) * 0.8); }
                svg { fill: none; stroke: currentColor; stroke-linecap: round; stroke-linejoin: round; }
            `;
            shadowRoot.appendChild(style);
            const panelContainer = document.createElement('div');
            panelContainer.className = 'panel-container';
            setHTML(panelContainer, `
                <div class="media-wrapper">
                    <button class="icon-btn play-pause-btn media-control" title="Play/Pause">${ICONS.play}${ICONS.pause}</button>
                    <div class="progress-bar-container media-control">
                        <div class="progress-bar-wrapper">
                            <div class="progress-hitbox"></div>
                            <input type="range" class="media-progress" min="0" max="100" value="0" step="0.1">
                        </div>
                        <span class="percent-label">0%</span>
                    </div>
                    <button class="speed-badge media-control" title="Playback Speed (Scroll/Right-click to reset). Click panel to unpin.">${"1.0x"}</button>
                    <button class="icon-btn skip-btn media-control" title="Skip to End">${ICONS.skip}</button>
                </div>`);
            shadowRoot.appendChild(panelContainer);
            Object.assign(appState.dom, {
                shadowHost, panelContainer,
                mediaWrapper: panelContainer.querySelector('.media-wrapper'),
                playPauseBtn: panelContainer.querySelector('.play-pause-btn'),
                progressBar: panelContainer.querySelector('.media-progress'),
                progressHitbox: panelContainer.querySelector('.progress-hitbox'),
                percentLabel: panelContainer.querySelector('.percent-label'),
                skipBtn: panelContainer.querySelector('.skip-btn'),
                speedBtn: panelContainer.querySelector('.speed-badge')
            });
        },
        bindEvents: function() {
            const { dom } = appState;
            dom.mediaWrapper.onmousedown = handleDragStart;
            dom.playPauseBtn.onclick = (e) => { if (isBlockingClick) { e.preventDefault(); e.stopPropagation(); return; } togglePlayPause(); };
            dom.skipBtn.onclick = (e) => { if (isBlockingClick) { e.preventDefault(); e.stopPropagation(); return; } handleSkipToEnd(); };
            dom.speedBtn.onmousedown = (e) => { if (isBlockingClick) { e.preventDefault(); e.stopPropagation(); return; } handleSpeedClick(e); };
            dom.speedBtn.oncontextmenu = (e) => e.preventDefault();
            dom.speedBtn.addEventListener('wheel', handleSpeedWheel, { passive: false });
            dom.progressHitbox.onmousedown = handleProgressInteractionStart;
            dom.progressHitbox.onwheel = handleProgressWheel;
            dom.panelContainer.addEventListener('mouseenter', () => clearTimeout(appState.inactivityTimer));
            dom.panelContainer.addEventListener('mouseleave', () => resetInactivityTimer());
            window.addEventListener('resize', () => { if (appState.isPanelVisible) applyPosition(true); });
        },
        init: async function() {
            View.create();
            View.bindEvents();
            await Persistence.loadState();
            if (appState.isPositionFixed && appState.settings.position) {
                const panel = appState.dom.panelContainer;
                panel.style.left = appState.settings.position.left;
                panel.style.top = appState.settings.position.top;
                applyPosition(false);
            }
            appState.isViewInitialized = true;
            updateMediaControlsUI();
        }
    };

    function mainLoop() {
        if (!appState.isViewInitialized) return;
        trackMediaPosition();
    }

    async function init() {
        await View.init();
        appState.trackingInterval = setInterval(mainLoop, TARGET_SCAN_INTERVAL);
        ['mousemove', 'mousedown', 'mouseup', 'wheel', 'drop', 'keydown'].forEach(eventName => {
            document.addEventListener(eventName, resetInactivityTimer, { capture: true, passive: true });
        });
        window.ZMediaPopupTeardown = () => {
             if (appState.trackingInterval) clearInterval(appState.trackingInterval);
             if (appState.dom.shadowHost) appState.dom.shadowHost.remove();
             window.ZMediaPopupInitialized = undefined;
        };
    }

    function main() {
        if (window.ZDB_READY) { init(); }
        else { document.addEventListener('ZDB_READY', init, { once: true }); }
    }

    if (document.body) { main(); }
    else { document.addEventListener('DOMContentLoaded', main); }
})();
'''
;




const zZone =
'''
if (typeof window.ZUIExplorerInitialized === 'undefined') {
    window.ZUIExplorerInitialized = true;
    (function() {
        let infoLabel, overlay;
        let currentTarget = null;
        let isPinned = false;
        let lastMousePos = { x: 0, y: 0 };
        let animationFrameId = null;
        let resizeObserver = null;
        let activityTimer = null;
        let isExplorerActive = true;
        const INACTIVITY_TIMEOUT = 1000;
        let policy;
        try {
            policy = window.trustedTypes.createPolicy('z-ui-explorer-policy', { createHTML: string => string });
        } catch(e) { policy = null; }
        const setSafeHTML = (element, html) => {
            if (policy) element.innerHTML = policy.createHTML(html);
            else element.innerHTML = html;
        };
        function createUI() {
            if (document.getElementById('z-explorer-overlay')) return;
            const style = document.createElement('style');
            style.textContent = `
                :root {
                    --z-explorer-highlight: #00BFFF;
                    --z-explorer-highlight-bg: rgba(0, 191, 255, 0.1);
                    --z-explorer-label-bg: rgba(30, 30, 30, 0.9);
                    --z-explorer-label-border: rgba(255, 255, 255, 0.1);
                    --z-explorer-success-color: #28a745;
                }
                .z-explorer-overlay {
                    position: absolute;
                    border: 1px solid var(--z-explorer-highlight);
                    box-sizing: border-box;
                    pointer-events: none;
                    z-index: 2147483640;
                    opacity: 0;
                    transition: all 0.05s linear;
                    border-radius: 4px;
                    background-color: transparent;
                }
                .z-explorer-overlay.visible { opacity: 1; }
                .z-explorer-overlay.pinned {
                    background-color: var(--z-explorer-highlight-bg);
                    border-style: solid;
                }
                .z-explorer-info-label {
                    position: absolute;
                    background-color: var(--z-explorer-label-bg);
                    border: 1px solid var(--z-explorer-label-border);
                    border-radius: 6px;
                    padding: 4px 10px;
                    font-family: 'Segoe UI', system-ui, sans-serif;
                    font-size: 13px;
                    line-height: 1.5;
                    color: #f0f0f0;
                    cursor: pointer;
                    pointer-events: all;
                    z-index: 2147483641;
                    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
                    opacity: 0;
                    transition: all 0.05s linear;
                    white-space: nowrap;
                    max-width: 400px;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    backdrop-filter: blur(8px);
                }
                .z-explorer-info-label.visible { opacity: 1; }
                .z-explorer-info-label:hover { background-color: #333; }
                .z-explorer-info-label.pinned {
                    background-color: var(--z-explorer-highlight);
                    border-color: #fff;
                    cursor: default;
                }
            `;
            document.head.appendChild(style);
            overlay = document.createElement('div');
            overlay.className = 'z-explorer-overlay';
            infoLabel = document.createElement('div');
            infoLabel.className = 'z-explorer-info-label';
            document.body.appendChild(overlay);
            document.body.appendChild(infoLabel);
            document.addEventListener('mousemove', handleMouseMove, true);
            infoLabel.onclick = handleLabelClick;
            infoLabel.oncontextmenu = handleLabelRightClick;
            resizeObserver = new ResizeObserver(entries => {
                for (let entry of entries) {
                    if (entry.target === currentTarget) {
                        updateOverlayPosition(currentTarget);
                    }
                }
            });
            resetActivityTimer();
        }
        function resetActivityTimer() {
            clearTimeout(activityTimer);
            if (!isExplorerActive) {
                isExplorerActive = true;
            }
            activityTimer = setTimeout(deactivateExplorer, INACTIVITY_TIMEOUT);
        }
        function deactivateExplorer() {
            isExplorerActive = false;
            hideOverlay();
        }
        function getElementIdentifier(element) {
            if (!element) return 'N/A';
            let name = element.getAttribute('aria-label') || element.id || element.getAttribute('title') || element.getAttribute('name');
            if (name) {
                if (element.id && name === element.id) name = '#' + name;
                return name.substring(0, 255);
            }
            if (element.className && typeof element.className === 'string') {
                const classes = element.className.trim().split(/\s+/).filter(c => c && typeof c === 'string').join('.');
                if (classes) return `.${classes}`.substring(0, 255);
            }
            return element.tagName.toLowerCase();
        }
        function getElementUnderMouse() {
            overlay.style.visibility = 'hidden';
            infoLabel.style.visibility = 'hidden';
            let element = document.elementFromPoint(lastMousePos.x, lastMousePos.y);
            overlay.style.visibility = 'visible';
            infoLabel.style.visibility = 'visible';
            while (element && element.shadowRoot) {
                const deeperElement = element.shadowRoot.elementFromPoint(lastMousePos.x, lastMousePos.y);
                if (deeperElement && deeperElement !== element) {
                    element = deeperElement;
                } else {
                    break;
                }
            }
            return element;
        }
        function handleMouseMove(e) {
            lastMousePos = { x: e.clientX, y: e.clientY };
            resetActivityTimer();
            if (!animationFrameId && !isPinned) {
                animationFrameId = requestAnimationFrame(updateTargetOnFrame);
            }
        }
        function updateTargetOnFrame() {
            animationFrameId = null;
            if (isPinned || !isExplorerActive) return;
            const element = findBestTarget(lastMousePos.x, lastMousePos.y);
            if (element && element !== currentTarget) {
                showOverlay(element);
            } else if (!element && currentTarget) {
                hideOverlay();
            }
        }
        function findBestTarget(x, y) {
            const element = getElementUnderMouse();
            if (!element || element === overlay || element === infoLabel || element === document.documentElement || element === document.body) {
                return null;
            }
            const rect = element.getBoundingClientRect();
            if (rect.width < 5 || rect.height < 5) return null;
            return element;
        }
        function updateOverlayPosition(element) {
            const rect = element.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0 || !document.body.contains(element)) {
                hideOverlay();
                return;
            }
            overlay.style.top = `${rect.top + window.scrollY}px`;
            overlay.style.left = `${rect.left + window.scrollX}px`;
            overlay.style.width = `${rect.width}px`;
            overlay.style.height = `${rect.height}px`;
            const labelRect = infoLabel.getBoundingClientRect();
            const margin = 8;
            let top = rect.top - labelRect.height - margin;
            if (top < 0) {
                top = rect.bottom + margin;
            }
            let left = rect.left + (rect.width / 2) - (labelRect.width / 2);
            left = Math.max(margin, Math.min(left, window.innerWidth - labelRect.width - margin));
            infoLabel.style.top = `${top + window.scrollY}px`;
            infoLabel.style.left = `${left + window.scrollX}px`;
            setSafeHTML(infoLabel, getElementIdentifier(element));
        }
        function showOverlay(element) {
            if (currentTarget) {
                resizeObserver.unobserve(currentTarget);
            }
            currentTarget = element;
            resizeObserver.observe(currentTarget);
            updateOverlayPosition(element);
            overlay.classList.add('visible');
            infoLabel.classList.add('visible');
        }
        function hideOverlay() {
            if (isPinned) return;
            overlay.classList.remove('visible');
            infoLabel.classList.remove('visible');
            if (currentTarget) {
                resizeObserver.unobserve(currentTarget);
                currentTarget = null;
            }
        }
        function handleLabelClick(e) {
            e.preventDefault();
            e.stopPropagation();
            isPinned = !isPinned;
            overlay.classList.toggle('pinned', isPinned);
            infoLabel.classList.toggle('pinned', isPinned);
            if (isPinned) {
                clearTimeout(activityTimer);
            } else {
                resetActivityTimer();
                handleMouseMove({clientX: lastMousePos.x, clientY: lastMousePos.y});
            }
        }
        function handleLabelRightClick(e) {
            e.preventDefault();
            e.stopPropagation();
            if (currentTarget) {
                const selector = getCssSelector(currentTarget);
                navigator.clipboard.writeText(selector)
                    .then(() => {
                        const originalText = infoLabel.textContent;
                        const originalBg = infoLabel.style.backgroundColor;
                        infoLabel.textContent = 'Selector Copied!';
                        infoLabel.style.backgroundColor = 'var(--z-explorer-highlight)';
                        setTimeout(() => {
                            infoLabel.textContent = originalText;
                            infoLabel.style.backgroundColor = originalBg;
                        }, 1200);
                    })
                    .catch(err => console.error('Failed to copy selector:', err));
            }
        }
        function getCssSelector(el) {
            if (!(el instanceof Element)) return;
            let path = [], parent;
            while (parent = el.parentNode) {
                let tag = el.tagName, siblings;
                path.unshift(
                    el.id ? `#${el.id.replace(/:/g, '\\\\:')}` : (
                        siblings = Array.from(parent.children).filter(child => child.tagName === tag),
                        siblings.length > 1 ? `${tag}:nth-child(${1 + siblings.indexOf(el)})` : tag
                    )
                );
                el = parent;
            }
            return `${path.join(' > ')}`.toLowerCase();
        }
        if (document.readyState === 'complete') {
            createUI();
        } else {
            window.addEventListener('load', createUI);
        }
    })();
}
''';










const zMiniAlbum =
'''
(function() {
    const oldHost = document.getElementById('z-mini-album-host');
    if (oldHost) { oldHost.remove(); }
    if (window.ZMiniAlbum_AddImage) { delete window.ZMiniAlbum_AddImage; }
})();
if (typeof window.ZMiniAlbumInitialized === 'undefined' || true) {
    window.ZMiniAlbumInitialized = true;
    (function() {
        const STORE_NAME = 'zMiniAlbumItems';
        const STATE_KEY = 'albumData';

        const MAX_SLOTS_VISIBLE = 5;
        const SLOT_SIZE = '40px'; // Thu nhỏ

        // Kích thước cố định cho Panel dọc (chủ yếu dựa vào chiều rộng)
        const FAB_SIZE = '48px'; // Thu nhỏ
        const PANEL_WIDTH_OPEN = '64px'; // 40px slot + 2*6px padding + 2*6px margin/gap (tổng khoảng 64px)

        const appState = {
            dom: {},
            albumItems: [], // { id, base64, prompt, type }
            scrollIndex: 0,
            isPanelOpen: false,
            previewItemIndex: -1 // Index của item đang xem ở chế độ fullscreen
        };

        const ICONS = {
            album: `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><line x1="3" y1="9" x2="21" y2="9"></line><line x1="9" y1="21" x2="9" y2="9"></line></svg>`,
            close: `<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>`,
            arrowUp: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="18 15 12 9 6 15"></polyline></svg>`,
            arrowDown: `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>`,
            closeFullscreen: `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>`,
            videoIcon: `<svg viewBox="0 0 24 24" width="12" height="12"><polygon points="23 7 16 12 23 17 23 7"></polygon><rect x="1" y="5" width="15" height="14" rx="2" ry="2"></rect></svg>`,
            previewNext: `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>`,
            previewPrev: `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>`
        };

        let policy;
        try { policy = window.trustedTypes.createPolicy('z-mini-album-policy', { createHTML: string => string }); }
        catch (e) { policy = null; }
        const setHTML = (element, html) => { if (policy) element.innerHTML = policy.createHTML(html); else element.innerHTML = html; };

        function getMediaType(dataUrl) {
            if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:')) return 'unknown';
            const mimeMatch = dataUrl.match(/^data:(\w+\/[-+.\w]+);/);
            if (!mimeMatch) return 'unknown';
            const mime = mimeMatch[1];

            if (/^image\/(jpeg|png|gif|webp|svg)/i.test(mime)) {
                return 'image';
            }
            // Thêm hỗ trợ video, thường là webm hoặc mp4
            if (/^video\/(webm|mp4|ogg|quicktime)/i.test(mime)) {
                return 'video';
            }
            return 'unknown';
        }

        const Persistence = {
            async performTransaction(mode, action) {
                if (!window.ZSharedDB || typeof window.ZSharedDB.performTransaction !== 'function') {
                    return Promise.reject(new Error("ZMiniAlbum Error: ZSharedDB core is not available."));
                }
                return window.ZSharedDB.performTransaction(STORE_NAME, mode, action);
            },
            async saveItems() {
                try {
                    // Chỉ lưu trữ 50 item gần nhất để tránh overload DB
                    const itemsToSave = appState.albumItems.slice(0, 50);
                    await this.performTransaction('readwrite', store => store.put({ id: STATE_KEY, items: itemsToSave }));
                } catch(e) { console.error("ZMiniAlbum: Failed to save items.", e); }
            },
            async loadItems() {
                try {
                    const savedState = await this.performTransaction('readonly', store => store.get(STATE_KEY));
                    if (savedState && Array.isArray(savedState.items)) {
                        appState.albumItems = savedState.items;
                    }
                } catch (e) { console.error("ZMiniAlbum: Failed to load items from DB.", e); }
            }
        };

        function createView() {
            if (document.getElementById('z-mini-album-host')) return;
            const shadowHost = document.createElement('div');
            shadowHost.id = 'z-mini-album-host';
            document.body.appendChild(shadowHost);
            const shadowRoot = shadowHost.attachShadow({ mode: 'open' });
            const style = document.createElement('style');
            style.textContent = `
                :host {
                  --bg-color: rgba(28, 28, 28, 0.9); --border-color: rgba(255, 255, 255, 0.1);
                  --slot-bg: rgba(0,0,0,0.3); --text-color: #e0e0e0; --accent-color: #0ea5e9;
                  --fab-size: ${FAB_SIZE}; /* 48px */
                  --slot-size: ${SLOT_SIZE}; /* 40px */
                  --open-width: ${PANEL_WIDTH_OPEN}; /* 64px */
                  --nav-btn-height: 24px;
                }
                .wrapper {
                    position: fixed;
                    bottom: 20px;
                    right: 20px;
                    z-index: 2147483646;
                    display: flex;
                    /* Mở theo chiều dọc (Stack lên trên) */
                    flex-direction: column;
                    align-items: flex-end;
                    gap: 10px;
                }
                .main-fab {
                    width: var(--fab-size); height: var(--fab-size);
                    background-color: var(--bg-color);
                    border: 1px solid var(--border-color);
                    border-radius: 50%;
                    display: flex; align-items: center; justify-content: center;
                    cursor: pointer;
                    box-shadow: 0 4px 15px rgba(0,0,0,0.4);
                    transition: all 0.3s cubic-bezier(0.25, 0.8, 0.25, 1);
                    color: var(--accent-color);
                    position: relative;
                }
                .main-fab:hover { transform: scale(1.1); }
                .image-count-badge {
                    position: absolute; top: 0; right: 0;
                    background-color: #ef4444; color: white; border-radius: 50%;
                    width: 20px; height: 20px; font-size: 11px; font-weight: bold;
                    display: flex; align-items: center; justify-content: center;
                    border: 2px solid var(--bg-color);
                    transform: scale(0); transition: transform 0.3s ease;
                }
                .wrapper.has-items .image-count-badge { transform: scale(1); }
                .panel-container {
                    display: flex;
                    /* Panel dọc */
                    flex-direction: column;
                    align-items: center;
                    background-color: var(--bg-color); border: 1px solid var(--border-color);
                    border-radius: 12px;
                    padding: 0;
                    gap: 6px;
                    backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);
                    box-shadow: 0 4px 15px rgba(0,0,0,0.4);

                    /* Tùy chỉnh panel ẩn/hiện (Ẩn theo chiều ngang) */
                    max-width: 0;
                    padding-left: 0;
                    padding-right: 0;
                    opacity: 0;
                    transition: all 0.3s cubic-bezier(0.25, 0.8, 0.25, 1);
                    height: auto; /* Chiều cao tự động */
                }
                .panel-container.open {
                    max-width: var(--open-width);
                    padding: 6px;
                    opacity: 1;
                }
                .nav-btn {
                    width: var(--slot-size);
                    height: var(--nav-btn-height);
                    display: flex; align-items: center; justify-content: center;
                    border-radius: 4px; /* Thay vì 50% */
                    cursor: pointer; color: #aaa; transition: all 0.2s;
                    background-color: rgba(255,255,255,0.05);
                }
                .nav-btn:hover:not(.disabled) { background: rgba(255,255,255,0.1); color: #fff; }
                .nav-btn.disabled { opacity: 0.3; pointer-events: none; }
                .slots-wrapper {
                    display: flex;
                    flex-direction: column; /* Stack dọc */
                    gap: 6px;
                    overflow: hidden;
                }
                .album-slot { width: var(--slot-size); height: var(--slot-size); background: var(--slot-bg); border-radius: 6px; border: 1px solid #444; overflow: hidden; position: relative; cursor: pointer; flex-shrink: 0; }
                .album-slot.empty { border-style: dashed; opacity: 0.3; cursor: default; }
                .album-slot img, .album-slot video { width: 100%; height: 100%; object-fit: cover; transition: transform 0.2s ease; }
                .album-slot:not(.empty):hover img, .album-slot:not(.empty):hover video { transform: scale(1.1); }
                .video-indicator {
                    position: absolute; bottom: 0; left: 0; padding: 2px 4px;
                    font-size: 10px; color: white; background: rgba(0,0,0,0.6);
                    border-top-right-radius: 4px; display: flex; align-items: center; gap: 2px;
                }
                .delete-btn { position: absolute; top: 2px; right: 2px; width: 16px; height: 16px; background: rgba(239, 68, 68, 0.8); color: #fff; border: none; border-radius: 50%; cursor: pointer; display: flex; align-items: center; justify-content: center; transform: scale(0); transition: all 0.2s; border: 1px solid black; z-index: 10; }
                .album-slot:not(.empty):hover .delete-btn { transform: scale(1); }
                .delete-btn:hover { transform: scale(1.2); }

                /* Fullscreen Preview */
                #z-album-preview { position: fixed; inset: 0; z-index: 2147483647; background: rgba(0, 0, 0, 0.9); display: flex; align-items: center; justify-content: center; opacity: 0; transition: opacity 0.3s; pointer-events: none; }
                #z-album-preview.visible { opacity: 1; pointer-events: auto; }
                #z-album-preview img, #z-album-preview video { max-width: 90%; max-height: 90%; object-fit: contain; }
                .preview-close-btn { position: absolute; top: 20px; right: 20px; cursor: pointer; color: white; z-index: 10; }
                .preview-nav-btn {
                    position: absolute; top: 50%; transform: translateY(-50%);
                    width: 50px; height: 100px; display: flex; align-items: center; justify-content: center;
                    cursor: pointer; color: white; opacity: 0.5; transition: opacity 0.2s;
                    background: rgba(0,0,0,0.2); z-index: 5;
                }
                .preview-nav-btn:hover { opacity: 1; background: rgba(0,0,0,0.4); }
                #z-album-preview-prev { left: 0; border-top-right-radius: 8px; border-bottom-right-radius: 8px; }
                #z-album-preview-next { right: 0; border-top-left-radius: 8px; border-bottom-left-radius: 8px; }
            `;
            shadowRoot.appendChild(style);
            const wrapper = document.createElement('div');
            wrapper.className = 'wrapper';
            const panel = document.createElement('div');
            panel.className = 'panel-container';
            setHTML(panel, `
                <button class="nav-btn prev-btn" id="z-album-prev-btn" title="Scroll Up">${ICONS.arrowUp}</button>
                <div class="slots-wrapper"></div>
                <button class="nav-btn next-btn" id="z-album-next-btn" title="Scroll Down">${ICONS.arrowDown}</button>
            `);
            const fab = document.createElement('div');
            fab.className = 'main-fab';
            setHTML(fab, `${ICONS.album}<div class="image-count-badge">0</div>`);
            wrapper.append(panel, fab);
            const preview = document.createElement('div');
            preview.id = 'z-album-preview';
            setHTML(preview, `
                <button class="preview-nav-btn" id="z-album-preview-prev" title="Previous Item">${ICONS.previewPrev}</button>
                <div id="z-album-preview-content"></div>
                <button class="preview-nav-btn" id="z-album-preview-next" title="Next Item">${ICONS.previewNext}</button>
                <button class="preview-close-btn" id="z-album-preview-close-btn" title="Close">${ICONS.closeFullscreen}</button>
            `);
            shadowRoot.appendChild(wrapper);
            shadowRoot.appendChild(preview);

            appState.dom = {
                wrapper, panel, shadowRoot, mainFab: fab,
                slotsWrapper: panel.querySelector('.slots-wrapper'),
                prevBtn: panel.querySelector('#z-album-prev-btn'),
                nextBtn: panel.querySelector('#z-album-next-btn'),
                badge: fab.querySelector('.image-count-badge'),
                preview,
                previewContent: preview.querySelector('#z-album-preview-content'),
                previewCloseBtn: preview.querySelector('#z-album-preview-close-btn'),
                previewPrevBtn: preview.querySelector('#z-album-preview-prev'),
                previewNextBtn: preview.querySelector('#z-album-preview-next'),
            };
        }

        function renderMedia(item) {
             let mediaHTML = '';
             let indicatorHTML = '';

             if (item.type === 'video') {
                // Sử dụng loop autoplay preload="metadata" để hiển thị frame đầu tiên
                mediaHTML = `<video src="${item.base64}" muted loop autoplay preload="metadata"></video>`;
                indicatorHTML = `<div class="video-indicator">${ICONS.videoIcon} Clip</div>`;
             } else {
                mediaHTML = `<img src="${item.base64}" alt="Album item">`;
             }

             const deleteBtnHTML = `<div class="delete-btn" title="Delete">${ICONS.close}</div>`;

             return mediaHTML + indicatorHTML + deleteBtnHTML;
        }

        function renderAlbum() {
            if (!appState.dom.slotsWrapper) return;
            setHTML(appState.dom.slotsWrapper, '');
            const totalItems = appState.albumItems.length;

            const startIndex = appState.scrollIndex;
            const endIndex = Math.min(totalItems, startIndex + MAX_SLOTS_VISIBLE);
            const visibleItems = appState.albumItems.slice(startIndex, endIndex);

            // Hiển thị các item đã có
            visibleItems.forEach((item, indexInView) => {
                const slot = document.createElement('div');
                slot.className = 'album-slot';
                slot.title = item.prompt || (item.type === 'video' ? 'Video Clip' : 'Image');

                setHTML(slot, renderMedia(item));

                // Tính toán index thực tế
                const actualIndex = startIndex + indexInView;
                slot.onclick = () => showPreview(actualIndex);

                const deleteBtn = slot.querySelector('.delete-btn');
                if(deleteBtn) deleteBtn.onclick = (e) => { e.stopPropagation(); removeItem(item.id); };

                appState.dom.slotsWrapper.appendChild(slot);
            });

            // YÊU CẦU: Thêm các slot trống để luôn đủ MAX_SLOTS_VISIBLE
            const slotsToFill = MAX_SLOTS_VISIBLE - visibleItems.length;
            for(let i = 0; i < slotsToFill; i++) {
                const slot = document.createElement('div');
                slot.className = 'album-slot empty';
                appState.dom.slotsWrapper.appendChild(slot);
            }

            if (appState.dom.prevBtn) {
                 // Đổi arrowLeft thành arrowUp, arrowRight thành arrowDown
                 appState.dom.prevBtn.classList.toggle('disabled', appState.scrollIndex === 0 || totalItems === 0);
            }
            if (appState.dom.nextBtn) {
                 appState.dom.nextBtn.classList.toggle('disabled', appState.scrollIndex + MAX_SLOTS_VISIBLE >= totalItems || totalItems <= MAX_SLOTS_VISIBLE);
            }

            appState.dom.badge.textContent = totalItems;
            appState.dom.wrapper.classList.toggle('has-items', totalItems > 0);
        }

        function addItem(base64Data, promptText) {
            const mediaType = getMediaType(base64Data);

            if (mediaType === 'unknown') {
                 console.error('[ZMiniAlbum] Unknown media type, skipping save.');
                 return;
            }

            const newItem = {
                id: Date.now() + Math.random(),
                base64: base64Data,
                prompt: promptText || '',
                type: mediaType
            };

            appState.albumItems.unshift(newItem);
            appState.scrollIndex = 0;
            renderAlbum();
            Persistence.saveItems();
        }

        function removeItem(itemId) {
            appState.albumItems = appState.albumItems.filter(item => item.id !== itemId);

            // Điều chỉnh scrollIndex nếu item bị xóa là item cuối cùng của trang trước
            const maxScroll = Math.max(0, appState.albumItems.length - MAX_SLOTS_VISIBLE);
            if (appState.scrollIndex > maxScroll) {
                 appState.scrollIndex = maxScroll;
            }

            renderAlbum();
            Persistence.saveItems();
        }

        function navigate(direction) {
            const maxScroll = Math.max(0, appState.albumItems.length - MAX_SLOTS_VISIBLE);
            let newIndex = appState.scrollIndex + (direction === 'next' ? 1 : -1);

            appState.scrollIndex = Math.max(0, Math.min(newIndex, maxScroll));
            renderAlbum();
        }

        // --- Fullscreen Navigation Logic ---

        function renderFullscreenPreview(index) {
            const item = appState.albumItems[index];
            if (!item) {
                 hidePreview();
                 return;
            }

            appState.previewItemIndex = index;

            // Dừng video cũ nếu có
            const oldVideo = appState.dom.previewContent.querySelector('video');
            if (oldVideo) {
                oldVideo.pause();
                oldVideo.removeAttribute('src');
                oldVideo.load();
            }

            let mediaTag;
            if (item.type === 'video') {
                mediaTag = `<video id="z-album-active-video" src="${item.base64}" controls autoplay muted loop playsinline></video>`;
            } else {
                mediaTag = `<img src="${item.base64}" alt="Preview Image">`;
            }

            setHTML(appState.dom.previewContent, mediaTag);
            appState.dom.preview.classList.add('visible');

            // Bật/Tắt nút điều hướng nếu chỉ có 1 item
            const total = appState.albumItems.length;
            appState.dom.previewPrevBtn.style.display = total > 1 ? 'flex' : 'none';
            appState.dom.previewNextBtn.style.display = total > 1 ? 'flex' : 'none';
        }

        function showPreview(index) {
            if (index < 0 || index >= appState.albumItems.length) return;
            renderFullscreenPreview(index);
        }

        function showNextItem() {
            if (appState.albumItems.length === 0) return;
            let newIndex = appState.previewItemIndex + 1;
            if (newIndex >= appState.albumItems.length) {
                newIndex = 0; // Loop over
            }
            renderFullscreenPreview(newIndex);
        }

        function showPrevItem() {
            if (appState.albumItems.length === 0) return;
            let newIndex = appState.previewItemIndex - 1;
            if (newIndex < 0) {
                newIndex = appState.albumItems.length - 1; // Loop over
            }
            renderFullscreenPreview(newIndex);
        }

        function hidePreview() {
            const videoElement = appState.dom.previewContent.querySelector('video');
            if (videoElement) {
                videoElement.pause();
                videoElement.removeAttribute('src');
                videoElement.load();
            }

            appState.dom.preview.classList.remove('visible');
            setHTML(appState.dom.previewContent, "");
            appState.previewItemIndex = -1;
        }

        function togglePanel() {
            appState.isPanelOpen = !appState.isPanelOpen;
            appState.dom.panel.classList.toggle('open', appState.isPanelOpen);
            if (appState.isPanelOpen) {
                 renderAlbum();
            }
        }

        window.ZMiniAlbum_AddImage = function(dataUrl, promptText) {
            if (typeof dataUrl === 'string' && dataUrl.startsWith('data:')) {
                addItem(dataUrl, promptText);
            }
        };

        function handleHostMessage(event) {
            try {
                const payload = JSON.parse(event.data);
                if (payload && payload.image && typeof payload.image === 'string' && payload.image.startsWith('data:')) {
                    addItem(payload.image, payload.prompt || '');
                }
            } catch(e) {
                if (typeof event.data === 'string' && event.data.startsWith('data:')) {
                    addItem(event.data, '');
                }
            }
        }

        async function initialize() {
            if (!document.body) { setTimeout(initialize, 50); return; }

            createView();

            await Persistence.loadItems();

            if (appState.dom.mainFab) appState.dom.mainFab.onclick = togglePanel;
            if (appState.dom.prevBtn) appState.dom.prevBtn.onclick = () => navigate('prev');
            if (appState.dom.nextBtn) appState.dom.nextBtn.onclick = () => navigate('next');
            if (appState.dom.previewCloseBtn) appState.dom.previewCloseBtn.onclick = hidePreview;
            if (appState.dom.preview) appState.dom.preview.onclick = (e) => {
                // Đảm bảo click vào nền đen mới đóng preview
                if (e.target === appState.dom.preview) hidePreview();
            };

            // BINDING NÚT NEXT/PREV TRONG FULLSCREEN
            if (appState.dom.previewNextBtn) appState.dom.previewNextBtn.onclick = showNextItem;
            if (appState.dom.previewPrevBtn) appState.dom.previewPrevBtn.onclick = showPrevItem;

            if (window.chrome && window.chrome.webview) {
                window.chrome.webview.addEventListener('message', handleHostMessage);
            }

            renderAlbum();
            console.log("ZMiniAlbum Initialized.");
        }

        function main() {
            if (window.ZDB_READY) {
                initialize();
            } else {
                document.addEventListener('ZDB_READY', initialize, { once: true });
            }
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', main);
        } else {
            main();
        }
    })();
}
'''
;








const zKernel =
'''
if (typeof window.ZKernelInitialized === 'true') {
} else {
    window.ZKernelInitialized = 'true';

    (function() {
        const STORE_NAME = 'zKernelScripts';
        const METADATA_STORE_NAME = 'zKernelState';
        const METADATA_KEY = 'zKernelMetadata';
        const DEFAULT_WIDTH = '400px';
        const DEFAULT_HEIGHT = '240px';

        let policy;
        try {
            policy = window.trustedTypes.createPolicy('z-kernel-policy', { createHTML: string => string, createScript: string => string });
        } catch(e) { policy = null; }

        const setSafeHTML = (element, html) => {
            if (!element) return;
            if (policy) element.innerHTML = policy.createHTML(html);
            else element.innerHTML = html;
        };

        const ICONS = {
            execute: `<svg viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>`,
            add: `<svg viewBox="0 0 24 24"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>`,
            trash: `<svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>`,
            sidebarToggle: `<svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><line x1="9" y1="3" x2="9" y2="21"></line></svg>`
        };

        function hashCode(str) {
            let hash = 0;
            if (str.length === 0) return '000000';
            for (let i = 0; i < str.length; i++) {
                const char = str.charCodeAt(i);
                hash = ((hash << 5) - hash) + char;
                hash |= 0;
            }
            return ('000000' + (hash >>> 0).toString(16)).slice(-6);
        }

        function generateIcon(id, code = '') {
            const salt = code.substring(0, 20);
            const hashInput = String(id) + salt;
            const hash = hashInput.split('').reduce((acc, char) => char.charCodeAt(0) + ((acc << 5) - acc), 0);
            const hue = (hash * 137.508) % 360;
            const saturation = 60 + (hash % 30);
            const lightness1 = 70 + (hash % 10);
            const lightness2 = 50 + (hash % 10);
            return `<div class="gen-icon" style="--h: ${hue}; --s: ${saturation}%; --l1: ${lightness1}%; --l2: ${lightness2}%;"></div>`;
        }

        function executeInGlobalScope(scriptCode) {
            const code = `'use strict';\n(function() { try { ${scriptCode} } catch(e) { console.error("[ZKernel] Execution Error:", e); } })();`;
            const script = document.createElement('script');
            if (policy && policy.createScript) { script.textContent = policy.createScript(code); }
            else { script.textContent = code; }
            (document.head || document.documentElement).appendChild(script);
            script.remove();
        }

        const State = {
            isPanelVisible: false, isSidebarCollapsed: true, scripts: [], activeScriptId: null, dom: {},
            isManualDragging: false,
            followerLoopId: null
        };

        const Persistence = {
            async performTransaction(storeName, mode, action) {
                if (!window.ZSharedDB || typeof window.ZSharedDB.performTransaction !== 'function') {
                    return Promise.reject(new Error("ZKernel Error: ZSharedDB core is not available."));
                }
                return window.ZSharedDB.performTransaction(storeName, mode, action);
            },
            async saveScript(script) { return this.performTransaction(STORE_NAME, 'readwrite', store => store.put(script)); },
            async loadAllScripts() {
                try {
                    return await this.performTransaction(STORE_NAME, 'readonly', store => store.getAll());
                } catch (e) { return []; }
            },
            async deleteScript(scriptId) { return this.performTransaction(STORE_NAME, 'readwrite', store => store.delete(scriptId)); },
            async saveMetadata() {
                try {
                    const metadata = { id: METADATA_KEY, activeScriptId: State.activeScriptId, isSidebarCollapsed: State.isSidebarCollapsed };
                    await this.performTransaction(METADATA_STORE_NAME, 'readwrite', store => store.put(metadata));
                } catch (e) {}
            },
            async loadMetadata() {
                try {
                    const data = await this.performTransaction(METADATA_STORE_NAME, 'readonly', store => store.get(METADATA_KEY));
                    if (data) {
                        State.activeScriptId = data.activeScriptId || null;
                        State.isSidebarCollapsed = data.isSidebarCollapsed !== false;
                    }
                } catch (e) {}
            }
        };

        const Actions = {
            togglePanelVisibility(forceState) {
                const shouldBeVisible = typeof forceState === 'boolean' ? forceState : !State.isPanelVisible;
                if (State.isPanelVisible !== shouldBeVisible) {
                    State.isPanelVisible = shouldBeVisible;
                    if (State.dom.panel && State.dom.shadowHost) {
                        if (shouldBeVisible) {
                            State.dom.shadowHost.style.display = 'block';
                            View.updatePosition();
                            State.dom.panel.style.display = 'flex';
                            requestAnimationFrame(() => { State.dom.panel.classList.add('visible'); });
                        } else {
                            State.dom.panel.classList.remove('visible');
                            setTimeout(() => {
                                if (!State.isPanelVisible) {
                                    State.dom.panel.style.display = 'none';
                                    State.dom.shadowHost.style.display = 'none';
                                }
                            }, 300);
                        }
                    }
                }
            },
            toggleSidebar() {
                State.isSidebarCollapsed = !State.isSidebarCollapsed;
                if (State.dom.panel) {
                    State.dom.panel.classList.toggle('sidebar-collapsed', State.isSidebarCollapsed);
                    requestAnimationFrame(() => View.updatePosition());
                }
                Persistence.saveMetadata();
            },
            async selectScript(scriptId) {
                if (State.activeScriptId === scriptId) return;
                await Actions.saveCurrentScriptContent();
                State.activeScriptId = scriptId;
                View.renderScriptList();
                View.renderEditor();
                Persistence.saveMetadata();
            },
            async addNewScript(isInitial = false) {
                const newId = Date.now();
                const newCode = ``;
                const newScript = { id: newId, code: newCode, icon: generateIcon(newId, newCode) };
                State.scripts.unshift(newScript);
                State.activeScriptId = newScript.id;
                await Persistence.saveScript(newScript);
                if (!isInitial) { View.render(); Persistence.saveMetadata(); }
            },
            async deleteScript(scriptId, event) {
                event.stopPropagation();
                const sortedScripts = [...State.scripts].sort((a,b) => a.id - b.id);
                const scriptIndex = sortedScripts.findIndex(s => s.id === scriptId);
                const displayName = `Script #${scriptIndex + 1}`;
                if (!confirm(`Delete ${displayName}?`)) return;

                State.scripts = State.scripts.filter(s => s.id !== scriptId);
                await Persistence.deleteScript(scriptId);
                if (State.activeScriptId === scriptId) {
                    if (State.scripts.length > 0) {
                        const newIndex = Math.max(0, scriptIndex - 1);
                        State.activeScriptId = sortedScripts[newIndex] ? sortedScripts[newIndex].id : sortedScripts[0].id;
                    } else { await Actions.addNewScript(false); return; }
                }
                View.render();
                Persistence.saveMetadata();
            },
            async saveCurrentScriptContent() {
                if (State.activeScriptId && State.dom.editor) {
                    const script = State.scripts.find(s => s.id === State.activeScriptId);
                    const newCode = State.dom.editor.value;
                    if (script && script.code !== newCode) {
                        script.code = newCode;
                        script.icon = generateIcon(script.id, newCode);
                        await Persistence.saveScript(script);
                        View.renderScriptList();
                        View.renderEditor();
                    }
                }
            },
            async executeCode() {
                await Actions.saveCurrentScriptContent();
                const scriptToRun = State.scripts.find(s => s.id === State.activeScriptId);
                if (!scriptToRun || !scriptToRun.code || !State.dom.headerTitle) return;

                if (window.chrome && window.chrome.webview) {
                    const sortedScripts = [...State.scripts].sort((a, b) => a.id - b.id);
                    const scriptIndex = sortedScripts.findIndex(s => s.id === scriptToRun.id);
                    const displayName = `Script #${scriptIndex + 1} [${hashCode(scriptToRun.code)}]`;
                    const payload = {
                        type: 'ZKernelLog',
                        data: { message: `[zKernel] Executing: ${displayName}` }
                    };
                    window.chrome.webview.postMessage(JSON.stringify(payload));
                }

                State.dom.headerTitle.textContent = 'Running...';
                State.dom.headerTitle.classList.add('running');
                try { executeInGlobalScope(scriptToRun.code); View.showExecutionFeedback(true); }
                catch (e) { View.showExecutionFeedback(false, e.message); }
                setTimeout(() => {
                    View.renderEditor();
                    if (State.dom.headerTitle) State.dom.headerTitle.classList.remove('running');
                }, 800);
            },
            async runAllScripts() {
                const sortedScripts = [...State.scripts].sort((a, b) => a.id - b.id);
                for (const [index, script] of sortedScripts.entries()) {
                    if (script && script.code) {
                        const displayName = `Script #${index + 1} [${hashCode(script.code)}]`;
                        if (window.chrome && window.chrome.webview) {
                            const payload = {
                                type: 'ZKernelLog',
                                data: { message: `[zKernel] Running: ${displayName}` }
                            };
                            window.chrome.webview.postMessage(JSON.stringify(payload));
                        }
                        try { executeInGlobalScope(script.code); }
                        catch (e) {}
                    }
                }
            }
        };

        window.ZKernel_Toggle = Actions.togglePanelVisibility;

        const View = {
            renderScriptList() {
                if (!State.dom.scriptList) return;
                const sortedScripts = [...State.scripts].sort((a, b) => a.id - b.id);
                const html = sortedScripts.map((script, index) => {
                    const isActive = script.id === State.activeScriptId;
                    const displayName = `Script #${index + 1} [${hashCode(script.code)}]`;
                    return `<div class="script-item ${isActive ? 'active' : ''}" data-script-id="${script.id}" title="${displayName}"><div class="icon">${script.icon}</div><div class="script-info"><div class="script-name">${displayName}</div></div><div class="delete-btn" title="Delete Script">${ICONS.trash}</div></div>`;
                }).join('');
                setSafeHTML(State.dom.scriptList, html);
            },
            renderEditor() {
                if (!State.dom.editor || !State.dom.mainArea || !State.dom.headerTitle) return;
                const script = State.scripts.find(s => s.id === State.activeScriptId);
                if (!script) {
                    State.dom.editor.value = "// Create a script with '+' button.";
                    State.dom.editor.disabled = true;
                    State.dom.mainArea.style.display = 'none';
                    State.dom.headerTitle.textContent = '';
                    return;
                }
                State.dom.mainArea.style.display = 'flex';
                State.dom.editor.value = script.code;
                State.dom.editor.disabled = false;
                if (!State.dom.headerTitle.classList.contains('running')) {
                    const sortedScripts = [...State.scripts].sort((a, b) => a.id - b.id);
                    const scriptIndex = sortedScripts.findIndex(s => s.id === script.id);
                    const displayName = `Script #${scriptIndex + 1} [${hashCode(script.code)}]`;
                    State.dom.headerTitle.textContent = displayName;
                    State.dom.headerTitle.title = displayName;
                }
            },
            render() { if (State.dom.panel) { this.renderScriptList(); this.renderEditor(); } },
            showExecutionFeedback(success, message = '') {
                const btn = State.dom.executeBtn;
                if (!btn || btn.classList.contains('feedback')) return;
                btn.classList.add('feedback', success ? 'success' : 'error');
                if (!success) { console.error("ZKernel Execution Failed:", message); }
                setTimeout(() => { btn.classList.remove('feedback', 'success', 'error'); }, 800);
            },
            updatePosition() {
                if (State.isManualDragging) return;
                const leaderHost = document.getElementById('z-keymapper-host');
                const host = State.dom.shadowHost;
                if (!host) return;
                let keyMapperFound = false;
                if (leaderHost && leaderHost.shadowRoot) {
                    const leaderPanel = leaderHost.shadowRoot.querySelector('.panel-container');
                    if (leaderPanel) {
                        keyMapperFound = true;
                        const leaderRect = leaderPanel.getBoundingClientRect();
                        const panelHeight = parseFloat(DEFAULT_HEIGHT);
                        Object.assign(host.style, { width: `${leaderRect.width}px`, height: DEFAULT_HEIGHT, left: `${leaderRect.left}px`, transform: 'none' });
                        const spaceBelow = window.innerHeight - leaderRect.bottom, spaceAbove = leaderRect.top;
                        if (spaceBelow >= panelHeight || spaceBelow >= spaceAbove) {
                            Object.assign(host.style, { top: `${leaderRect.bottom}px`, bottom: 'auto' });
                            if(State.dom.panel) State.dom.panel.style.borderRadius = '0 0 12px 12px';
                        } else {
                            Object.assign(host.style, { bottom: `${window.innerHeight - leaderRect.top}px`, top: 'auto' });
                            if(State.dom.panel) State.dom.panel.style.borderRadius = '12px 12px 0 0';
                        }
                        return;
                    }
                }
                if (!keyMapperFound) {
                     Object.assign(host.style, { width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, left: '50%', transform: 'translateX(-50%)', bottom: '50px', top: 'auto' });
                     if(State.dom.panel) State.dom.panel.style.borderRadius = '12px';
                }
            }
        };

        function onDragStart(e) {
            if (!e.target.closest('.z-kernel-sidebar, .main-header') || e.target.closest('button')) return;
            e.preventDefault();
            State.isManualDragging = true;
            const host = State.dom.shadowHost;
            const rect = host.getBoundingClientRect();
            const dragStartPos = { x: e.clientX - rect.left, y: e.clientY - rect.top };
            if(State.dom.panel) State.dom.panel.classList.add('dragging');
            function onDragMove(e) {
                requestAnimationFrame(() => {
                    Object.assign(host.style, { left: `${e.clientX - dragStartPos.x}px`, top: `${e.clientY - dragStartPos.y}px`, bottom: 'auto', right: 'auto', transform: 'none' });
                    if(State.dom.panel) State.dom.panel.style.borderRadius = '12px';
                });
            }
            function onDragEnd() {
                document.removeEventListener('mousemove', onDragMove);
                document.removeEventListener('mouseup', onDragEnd);
                if(State.dom.panel) State.dom.panel.classList.remove('dragging');
                setTimeout(() => { State.isManualDragging = false; }, 100);
            }
            document.addEventListener('mousemove', onDragMove);
            document.addEventListener('mouseup', onDragEnd, { once: true });
        }

        async function init() {
            const shadowHost = document.createElement('div');
            shadowHost.id = 'z-kernel-host';
            Object.assign(shadowHost.style, { position: 'fixed', zIndex: '2147483646', width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT, pointerEvents: 'none', display: 'none' });
            document.body.appendChild(shadowHost);
            const shadowRoot = shadowHost.attachShadow({ mode: 'open' });
            const style = document.createElement('style');
            style.textContent = `
                :root { --bg: #18181B; --sidebar-bg: rgba(39, 39, 42, 0.5); --border: rgba(255, 255, 255, 0.1); --text-primary: #e4e4e7; --text-secondary: #a1a1aa; --accent: #a78bfa; --accent-hover: #9d78f9; --success: #34d399; --error: #f87171; }
                #z-kernel-panel { position: absolute; inset: 0; display: none; flex-direction: column; background-color: rgba(24, 24, 27, 0.8); border: 1px solid var(--border); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--text-primary); backdrop-filter: blur(16px) saturate(1.5); overflow: hidden; opacity: 0; pointer-events: none; transition: opacity 0.3s ease; }
                #z-kernel-panel.visible { opacity: 1; pointer-events: auto; }
                .dragging { transition: none !important; user-select: none; }
                .z-kernel-content { display: flex; flex-grow: 1; min-height: 0; }
                .z-kernel-sidebar { width: 180px; flex-shrink: 0; background-color: var(--sidebar-bg); display: flex; flex-direction: column; border-right: 1px solid var(--border); transition: width 0.3s ease; cursor: grab; }
                .z-kernel-script-list { flex-grow: 1; overflow-y: auto; padding: 8px; scrollbar-width: none; }
                .z-kernel-script-list::-webkit-scrollbar { display: none; }
                .script-item { display: flex; align-items: center; padding: 6px; cursor: pointer; transition: all 0.2s; border-radius: 6px; margin-bottom: 4px; border: 1px solid transparent; position: relative; }
                .script-item:hover { background-color: rgba(255,255,255,0.05); }
                .script-item.active { background-color: rgba(167, 139, 250, 0.25); border-color: rgba(167, 139, 250, 0.5); box-shadow: 0 0 8px rgba(167, 139, 250, 0.2); }
                .script-item.active .script-name { color: #fff; font-weight: 600; }
                .script-item.active .icon { transform: scale(1.1); filter: brightness(1.2); }
                .script-item.active::before { content: ''; position: absolute; left: -8px; top: 8px; bottom: 8px; width: 3px; background-color: var(--accent); border-radius: 3px; }
                .icon { width: 28px; height: 28px; flex-shrink: 0; margin-right: 10px; transition: transform 0.2s, filter 0.2s; }
                .gen-icon { width: 100%; height: 100%; border-radius: 6px; background: linear-gradient(45deg, hsl(var(--h), var(--s), var(--l1)), hsl(calc(var(--h) + 40), var(--s), var(--l2))); }
                .script-info { flex-grow: 1; min-width: 0; }
                .script-name { font-size: 13px; font-weight: 500; color: var(--text-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
                .delete-btn { width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border-radius: 50%; color: #666; transition: all 0.2s; flex-shrink: 0; margin-left: 4px; }
                .script-item:hover .delete-btn { color: var(--error); }
                .delete-btn:hover { background-color: rgba(248, 113, 113, 0.1); }
                .z-kernel-main { flex-grow: 1; display: flex; flex-direction: column; position: relative; min-width: 0; }
                .main-header { display: flex; align-items: center; padding: 0 8px; height: 40px; flex-shrink: 0; user-select: none; border-bottom: 1px solid var(--border); cursor: grab; }
                .header-btn { background: none; border: none; color: var(--text-secondary); cursor: pointer; padding: 6px; border-radius: 50%; display: flex; transition: all 0.2s; }
                .header-btn:hover { background: rgba(255,255,255,0.1); color: var(--text-primary); }
                .header-btn:active { transform: scale(0.95); }
                .header-spacer { flex-grow: 1; min-width: 10px; text-align: center; }
                .header-title { font-size: 12px; color: var(--text-secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 200px; transition: all 0.2s ease-in-out; }
                .header-title.running { color: var(--success); font-weight: bold; letter-spacing: 0.5px; transform: scale(1.05); }
                .sidebar-collapsed .header-title { opacity: 1; visibility: visible; }
                #z-kernel-panel:not(.sidebar-collapsed) .header-title { opacity: 0; visibility: hidden; }
                #execute-btn { padding: 8px; background-color: transparent; border: 1px solid var(--accent); color: var(--accent); font-weight: 600; box-shadow: 0 0 10px rgba(167, 139, 250, 0.3); }
                #execute-btn:hover { background-color: var(--accent); color: white; transform: scale(1.05); }
                #execute-btn.feedback.success { background-color: var(--success); border-color: var(--success); color: white; }
                #execute-btn.feedback.error { background-color: var(--error); border-color: var(--error); color: white; }
                #z-kernel-editor { flex-grow: 1; background-color: transparent; border: none; padding: 10px; color: #d4d4d4; outline: none; resize: none; font-family: 'Fira Code', 'Courier New', monospace; font-size: 13px; line-height: 1.6; }
                .sidebar-collapsed .z-kernel-sidebar { width: 45px; }
                .sidebar-collapsed .script-item { justify-content: center; }
                .sidebar-collapsed .script-info, .sidebar-collapsed .delete-btn { display: none; }
                .sidebar-collapsed .icon { margin-right: 0; }
                svg { width: 1em; height: 1em; fill: none; stroke: currentColor; stroke-width: 2.5; stroke-linecap: round; stroke-linejoin: round; }
            `;
            shadowRoot.appendChild(style);
            const panel = document.createElement('div');
            panel.id = 'z-kernel-panel';
            setSafeHTML(panel, `<div class="z-kernel-content"><aside class="z-kernel-sidebar"><div class="z-kernel-script-list"></div></aside><main class="z-kernel-main"><header class="main-header"><button id="sidebar-toggle-btn" class="header-btn" title="Toggle Sidebar">${ICONS.sidebarToggle}</button><button id="add-script-btn" class="header-btn" title="New Script">${ICONS.add}</button><div class="header-spacer"><span class="header-title"></span></div><button id="execute-btn" class="header-btn">${ICONS.execute}</button></header><textarea id="z-kernel-editor" spellcheck="false" placeholder="Your JavaScript code goes here..."></textarea></main></div>`);
            shadowRoot.appendChild(panel);
            Object.assign(State.dom, { panel, scriptList: panel.querySelector('.z-kernel-script-list'), mainArea: panel.querySelector('.z-kernel-main'), editor: panel.querySelector('#z-kernel-editor'), executeBtn: panel.querySelector('#execute-btn'), addBtn: panel.querySelector('#add-script-btn'), sidebarToggleBtn: panel.querySelector('#sidebar-toggle-btn'), headerTitle: panel.querySelector('.header-title'), shadowHost });

            const eventHandlers = [ [State.dom.panel, 'mousedown', onDragStart], [State.dom.scriptList, 'click', (e) => { const item = e.target.closest('.script-item'); const delBtn = e.target.closest('.delete-btn'); if (delBtn && item) { Actions.deleteScript(parseInt(item.dataset.scriptId), e); } else if (item) { Actions.selectScript(parseInt(item.dataset.scriptId)); } }], [State.dom.addBtn, 'click', () => Actions.addNewScript(false)], [State.dom.executeBtn, 'click', Actions.executeCode], [State.dom.sidebarToggleBtn, 'click', Actions.toggleSidebar], [State.dom.editor, 'blur', Actions.saveCurrentScriptContent], [window, 'beforeunload', Actions.saveCurrentScriptContent] ];
            eventHandlers.forEach(([el, evt, handler]) => el.addEventListener(evt, handler));

            await Persistence.loadMetadata();
            State.scripts = (await Persistence.loadAllScripts());
            if (State.scripts.length === 0) { await Actions.addNewScript(true); }
            if (!State.scripts.find(s => s.id === State.activeScriptId)) { State.activeScriptId = State.scripts.length > 0 ? State.scripts[0].id : null; }
            if(State.dom.panel) State.dom.panel.classList.toggle('sidebar-collapsed', State.isSidebarCollapsed);
            View.render();
            await Actions.runAllScripts();

            function followerLoop() {
                if (State.isPanelVisible || State.isManualDragging) {
                     View.updatePosition();
                }
                State.followerLoopId = requestAnimationFrame(followerLoop);
            }
            State.followerLoopId = requestAnimationFrame(followerLoop);
        }

        function main() {
            if (window.ZDB_READY) { init(); }
            else { document.addEventListener('ZDB_READY', init, { once: true }); }
        }

        if (document.readyState === 'complete') { main(); }
        else { window.addEventListener('load', main); }
    })();
}
'''
;














const zMediaStudio =
'''
if (typeof window.ZMediaStudioInitialized !== 'undefined') {
    if (window.ZMediaStudioTeardown) window.ZMediaStudioTeardown();
}
window.ZMediaStudioInitialized = true;

(function() {
    let policy;
    const policyName = 'z-media-studio-policy#' + Date.now();
    try {
        if (window.trustedTypes && window.trustedTypes.createPolicy) {
            policy = window.trustedTypes.createPolicy(policyName, { createHTML: string => string });
        }
    } catch (e) {
        policy = window.trustedTypes.getPolicy(policyName);
    }
    const setSafeHTML = (element, html) => { if (!element) return; if (policy) { element.innerHTML = policy.createHTML(html); } else { element.innerHTML = html; } };
    const removeAllChildren = (element) => { if (!element) return; while (element.firstChild) { element.removeChild(element.firstChild); } };

    const ICONS = {
        studio: `<svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>`,
        capture: `<svg viewBox="0 0 24 24"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"></path><circle cx="12" cy="13" r="4"></circle></svg>`,
        record: `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"></circle></svg>`,
        stop: `<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12"></rect></svg>`,
        extract: `<svg viewBox="0 0 24 24"><path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path></svg>`,
        trash: `<svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>`,
        close: `<svg viewBox="0 0 24 24"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>`,
        download: `<svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>`
    };

    const State = {
        dom: {}, isPanelVisible: false, videos: [], capturedItems: [],
        activeVideoId: null, activeRecorder: null, activeExtractor: null,
        headerStatusTimeout: null, dragInfo: null,
        dragDropState: { isDragging: false, draggedItemId: null },
        nextItemId: 0
    };

    const getNextItemId = () => State.nextItemId++;
    const formatTime = (seconds) => { if (isNaN(seconds) || seconds === Infinity) return '...'; const floorSeconds = Math.floor(seconds); const min = Math.floor(floorSeconds / 60); const sec = floorSeconds % 60; return `${min}:${sec.toString().padStart(2, '0')}`; };
    const convertBlobToDataURL = (blob) => new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = () => reject(reader.error); reader.readAsDataURL(blob); });

    const Actions = {
        togglePanel() { State.isPanelVisible = !State.isPanelVisible; State.dom.panel.classList.toggle('visible', State.isPanelVisible); State.dom.fab.classList.toggle('active', State.isPanelVisible); if (State.isPanelVisible) Actions.scanForMedia(); },
        scanForMedia() {
            State.videos = [];
            document.querySelectorAll('video').forEach((video, index) => { if (video.readyState > 0 && video.videoWidth > 50 && video.videoHeight > 50 && !isNaN(video.duration) && video.duration > 0.5) { video.dataset.zStudioId = index; State.videos.push({ id: index, element: video, width: video.videoWidth, height: video.videoHeight, duration: video.duration }); } });
            View.renderVideoList();
            if (State.videos.length > 0 && (State.activeVideoId === null || !State.videos.find(v => v.id === State.activeVideoId))) { Actions.selectVideo(State.videos[0].id); } else if (State.videos.length === 0) { Actions.selectVideo(null); }
        },
        selectVideo(videoId) { State.activeVideoId = videoId; View.renderVideoList(); View.renderControls(); View.renderGalleries(); },
        captureFrame() {
            const activeVideo = State.videos.find(v => v.id === State.activeVideoId); if (!activeVideo || State.activeRecorder || State.activeExtractor) return;
            const video = activeVideo.element; const wasPaused = video.paused; if (!wasPaused) video.pause();
            try {
                const canvas = document.createElement('canvas'); canvas.width = video.videoWidth; canvas.height = video.videoHeight;
                const ctx = canvas.getContext('2d'); ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                const dataURL = canvas.toDataURL('image/jpeg', 0.9);
                State.capturedItems.unshift({ id: getNextItemId(), type: 'image', data: dataURL, sourceVideoId: activeVideo.id, label: `Frame at ${video.currentTime.toFixed(2)}s` });
                View.renderGalleries(); View.renderHeaderStatus(`Captured frame`, 'success');
            } catch (e) { View.renderHeaderStatus(`Capture Failed`, 'error'); }
            finally { if (!wasPaused) video.play().catch(()=>{}); }
        },
        toggleRecording() {
            if (State.activeRecorder) { if(State.activeRecorder.state === 'recording') State.activeRecorder.stop(); return; }
            const activeVideo = State.videos.find(v => v.id === State.activeVideoId); if (!activeVideo || State.activeExtractor) return;
            const video = activeVideo.element; let stream; try { stream = video.captureStream ? video.captureStream() : video.mozCaptureStream(); } catch (e) { View.renderHeaderStatus("Recording not supported", "error"); return; } if (!stream) { View.renderHeaderStatus("Recording not supported", "error"); return; }
            const originalState = { time: video.currentTime, paused: video.paused, muted: video.muted, loop: video.loop }; const recordedChunks = []; const mediaRecorder = new MediaRecorder(stream, { mimeType: 'video/webm' }); State.activeRecorder = mediaRecorder; let animationFrameId = null; let lastTime = -1;
            const cleanup = () => { if (animationFrameId) cancelAnimationFrame(animationFrameId); video.pause(); video.currentTime = originalState.time; video.muted = originalState.muted; video.loop = originalState.loop; if (!originalState.paused) video.play().catch(()=>{}); State.activeRecorder = null; View.renderControls(); };
            mediaRecorder.ondataavailable = (event) => { if (event.data.size > 0) recordedChunks.push(event.data); };
            mediaRecorder.onstart = () => {
                View.renderControls(); const totalDuration = video.duration;
                const updateProgress = () => { if (!State.activeRecorder || State.activeRecorder.state !== 'recording') return; const currentTime = video.currentTime; if (video.ended || (originalState.loop && lastTime > 0 && currentTime < lastTime && (lastTime - currentTime > 0.5))) { State.activeRecorder.stop(); return; } lastTime = currentTime; const progress = (currentTime / totalDuration) * 100; View.renderHeaderStatus(`Recording... ${formatTime(currentTime)}`, 'progress', progress); animationFrameId = requestAnimationFrame(updateProgress); };
                animationFrameId = requestAnimationFrame(updateProgress);
            };
            mediaRecorder.onstop = () => {
                const blob = new Blob(recordedChunks, { type: 'video/webm' }); const blobURL = URL.createObjectURL(blob); const fileSize = (blob.size / 1024 / 1024).toFixed(2); const newItem = { id: getNextItemId(), type: 'video', data: blobURL, sourceVideoId: activeVideo.id, label: `Clip (${fileSize} MB)`, isConverting: true };
                State.capturedItems.unshift(newItem); View.renderGalleries(); View.renderHeaderStatus(`Clip recorded. Processing...`, 'success');
                convertBlobToDataURL(blob).then(dataURL => { const itemInState = State.capturedItems.find(item => item.id === newItem.id); if (itemInState) { URL.revokeObjectURL(itemInState.data); itemInState.data = dataURL; itemInState.isConverting = false; View.renderGalleries(); }
                }).catch(err => { const itemInState = State.capturedItems.find(item => item.id === newItem.id); if (itemInState) { itemInState.label = `Clip (Processing Failed)`; itemInState.isConverting = false; View.renderGalleries(); } });
                cleanup();
            };
            video.muted = true; video.loop = false; video.play().then(() => mediaRecorder.start()).catch(e => { View.renderHeaderStatus(`Record Failed`, 'error'); cleanup(); });
        },
        toggleExtracting() {
            if (State.activeExtractor) { State.activeExtractor.stop = true; return; } if (State.activeRecorder) return;
            const activeVideo = State.videos.find(v => v.id === State.activeVideoId); if (!activeVideo) return;
            const video = activeVideo.element; const interval = 1.0; let lastCaptureTime = video.currentTime - interval; let capturedCount = 0; State.activeExtractor = { stop: false };
            const originalState = { time: video.currentTime, paused: video.paused, muted: video.muted, loop: video.loop, playbackRate: video.playbackRate }; let animationFrameId = null; let lastTime = -1;
            const cleanup = (finalMessage) => { if (animationFrameId) cancelAnimationFrame(animationFrameId); video.pause(); video.playbackRate = originalState.playbackRate; video.currentTime = originalState.time; video.muted = originalState.muted; video.loop = originalState.loop; if (!originalState.paused) video.play().catch(()=>{}); State.activeExtractor = null; View.renderControls(); View.renderHeaderStatus(finalMessage, 'success'); };
            const extractionLoop = () => { if (State.activeExtractor.stop) { cleanup(`${capturedCount} frames captured.`); return; } const currentTime = video.currentTime; if (video.ended || (originalState.loop && lastTime > 0 && currentTime < lastTime && (lastTime - currentTime > 0.5))) { cleanup(`${capturedCount} frames captured.`); return; } lastTime = currentTime; View.renderHeaderStatus(`Extracting... ${Math.round((currentTime / video.duration) * 100)}%`, 'progress', (currentTime / video.duration) * 100);
                if (currentTime >= lastCaptureTime + interval) {
                    lastCaptureTime = currentTime;
                    try { const canvas = document.createElement('canvas'); canvas.width = video.videoWidth; canvas.height = video.videoHeight; const ctx = canvas.getContext('2d'); ctx.drawImage(video, 0, 0, canvas.width, canvas.height); const dataURL = canvas.toDataURL('image/jpeg', 0.8); State.capturedItems.unshift({ id: getNextItemId(), type: 'image', data: dataURL, sourceVideoId: activeVideo.id, label: `Extracted at ${currentTime.toFixed(1)}s` }); capturedCount++; View.renderGalleries(); } catch(e){}
                }
                animationFrameId = requestAnimationFrame(extractionLoop);
            };
            video.muted = true; video.loop = false; video.playbackRate = 16.0; video.play().then(() => { View.renderControls(); animationFrameId = requestAnimationFrame(extractionLoop); }).catch(e => { View.renderHeaderStatus(`Extraction Failed`, 'error'); cleanup(''); });
        },
        deleteCapturedItem(itemId, event) { event.stopPropagation(); const item = State.capturedItems.find(i => i.id === itemId); if (item && item.type === 'video' && item.data.startsWith('blob:')) { URL.revokeObjectURL(item.data); } State.capturedItems = State.capturedItems.filter(i => i.id !== itemId); View.renderGalleries(); },
        downloadItem(itemId, event) { event.stopPropagation(); const item = State.capturedItems.find(i => i.id === itemId); if (!item) return; const link = document.createElement('a'); link.href = item.data; const extension = item.type === 'image' ? 'jpg' : 'webm'; link.download = `zstudio-capture-${item.id}.${extension}`; document.body.appendChild(link); link.click(); document.body.removeChild(link); },
        showFullscreen(item) { const content = item.type === 'image' ? `<img src="${item.data}" />` : `<video src="${item.data}" controls autoplay loop></video>`; setSafeHTML(State.dom.fullscreenContent, content); State.dom.fullscreenViewer.classList.add('visible'); },
        hideFullscreen() { setSafeHTML(State.dom.fullscreenContent, ''); State.dom.fullscreenViewer.classList.remove('visible'); }
    };

    const View = {
        renderVideoList() { let html = ''; if (State.videos.length === 0) { html = '<div class="empty-list">No videos found.</div>'; } else { State.videos.forEach(video => { const isActive = video.id === State.activeVideoId; const durationText = video.duration === Infinity ? 'LIVE' : formatTime(video.duration); html += `<div class="video-item ${isActive ? 'active' : ''}" data-video-id="${video.id}"><div class="video-info"><div class="video-name">Video #${video.id + 1}</div><div class="video-details">${video.width}x${video.height} | ${durationText}</div></div></div>`; }); } setSafeHTML(State.dom.videoList, html); },
        renderControls() {
            const activeVideo = State.videos.find(v => v.id === State.activeVideoId); if (!activeVideo) { State.dom.controls.style.display = 'none'; return; } State.dom.controls.style.display = 'flex'; const isRecording = State.activeRecorder && State.activeRecorder.state === 'recording'; const isExtracting = !!State.activeExtractor;
            setSafeHTML(State.dom.recordBtn, isRecording ? ICONS.stop : ICONS.record); State.dom.recordBtn.title = isRecording ? 'Stop' : 'Record'; State.dom.recordBtn.classList.toggle('recording', isRecording);
            setSafeHTML(State.dom.extractBtn, isExtracting ? ICONS.stop : ICONS.extract); State.dom.extractBtn.title = isExtracting ? 'Stop' : 'Extract Frames'; State.dom.extractBtn.classList.toggle('recording', isExtracting);
            State.dom.recordBtn.disabled = isExtracting; State.dom.captureBtn.disabled = isRecording || isExtracting; State.dom.extractBtn.disabled = isRecording;
        },
        renderGalleries() {
            const gallery = State.dom.gallery; removeAllChildren(gallery);
            const itemsToShow = State.activeVideoId !== null ? State.capturedItems.filter(item => item.sourceVideoId === State.activeVideoId) : [];
            if (itemsToShow.length === 0) { const emptyEl = document.createElement('div'); emptyEl.className = 'empty-gallery'; emptyEl.textContent = 'Captured items appear here.'; gallery.appendChild(emptyEl); return; }
            itemsToShow.forEach(item => {
                const itemEl = document.createElement('div'); itemEl.className = 'gallery-item'; itemEl.dataset.itemId = item.id; itemEl.title = item.label; itemEl.draggable = true;
                const itemContent = item.type === 'image' ? `<img src="${item.data}" draggable="false" />` : `<video src="${item.data}" muted loop autoplay draggable="false"></video>`;
                const convertingOverlay = item.isConverting ? '<div class="gallery-overlay">Processing...</div>' : '';
                const controls = `<div class="gallery-item-controls"><button class="item-action-btn download-btn" title="Download">${ICONS.download}</button><button class="item-action-btn delete-item-btn" title="Delete">${ICONS.trash}</button></div>`;
                setSafeHTML(itemEl, `${itemContent}${convertingOverlay}<div class="gallery-label">${item.label}</div>${controls}`);
                gallery.appendChild(itemEl);
            });
        },
        renderHeaderStatus(text, type = 'info', progress = -1) { if (State.headerStatusTimeout) clearTimeout(State.headerStatusTimeout); if (!text) { setSafeHTML(State.dom.headerTitle, 'Media Studio'); State.dom.headerProgress.style.width = '0%'; State.dom.header.className = 'studio-header'; return; } setSafeHTML(State.dom.headerTitle, text); State.dom.header.className = 'studio-header'; State.dom.header.classList.add(`status-${type}`); if (progress >= 0) { State.dom.headerProgress.style.width = `${progress}%`; } else { State.dom.headerProgress.style.width = type === 'success' || type === 'error' ? '100%' : '0%'; } if (type === 'success' || type === 'error') { State.headerStatusTimeout = setTimeout(() => { View.renderHeaderStatus(''); }, 3000); } }
    };

    function createView() {
        const shadowHost = document.createElement('div'); shadowHost.id = 'z-media-studio-host'; document.body.appendChild(shadowHost);
        const shadowRoot = shadowHost.attachShadow({ mode: 'open' });
        const style = document.createElement('style');
        style.textContent = `
            :host { --bg: #18181B; --sidebar-bg: rgba(39, 39, 42, 0.5); --border: rgba(255, 255, 255, 0.1); --text-primary: #e4e4e7; --text-secondary: #a1a1aa; --accent: #007acc; --danger: #ef4444; --success: #34d399; --panel-width: 650px; --panel-height: 450px; --sidebar-width: 200px; }
            #z-media-studio-fab { position: fixed; bottom: 20px; right: 80px; width: 50px; height: 50px; background-color: var(--accent); border-radius: 50%; display: flex; align-items: center; justify-content: center; z-index: 2147483646; cursor: pointer; color: white; box-shadow: 0 4px 15px rgba(0,0,0,0.4); transition: all 0.3s ease; }
            #z-media-studio-fab.active, #z-media-studio-fab:hover { transform: scale(1.1); background-color: #0099ff; }
            #z-media-studio-panel { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); width: var(--panel-width); height: var(--panel-height); background-color: rgba(24, 24, 27, 0.85); border: 1px solid var(--border); border-radius: 12px; z-index: 2147483645; display: flex; flex-direction: column; font-family: 'Segoe UI', sans-serif; color: var(--text-primary); backdrop-filter: blur(16px) saturate(1.5); box-shadow: 0 10px 40px rgba(0,0,0,0.5); overflow: hidden; opacity: 0; pointer-events: none; transition: opacity 0.3s ease, transform 0.3s ease, width 0s, height 0s; resize: both; }
            #z-media-studio-panel.visible { opacity: 1; pointer-events: auto; transform: translate(-50%, -50%) scale(1); }
            .studio-header { display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background: rgba(0,0,0,0.2); flex-shrink: 0; user-select: none; position: relative; overflow: hidden; cursor: move; }
            .header-progress-bar { position: absolute; bottom: 0; left: 0; height: 3px; width: 0%; background-color: var(--accent); transition: width 0.2s linear, background-color 0.3s ease; }
            .studio-header.status-success .header-progress-bar { background-color: var(--success); } .studio-header.status-error .header-progress-bar { background-color: var(--danger); }
            .header-btn { background: none; border: none; color: var(--text-secondary); cursor: pointer; padding: 6px; border-radius: 50%; display: flex; transition: all 0.2s; }
            .header-btn:hover { background: rgba(255,255,255,0.1); color: var(--text-primary); }
            .studio-content { display: flex; flex-grow: 1; min-height: 0; }
            .studio-sidebar { width: var(--sidebar-width); flex-shrink: 0; background-color: var(--sidebar-bg); display: flex; flex-direction: column; border-right: 1px solid var(--border); }
            .video-list { flex-grow: 1; overflow-y: auto; padding: 8px; }
            .video-item { display: flex; align-items: center; padding: 8px; cursor: pointer; border-radius: 6px; margin-bottom: 4px; position: relative; }
            .video-item:hover { background-color: rgba(255,255,255,0.05); } .video-item.active { background-color: rgba(0, 122, 204, 0.2); }
            .video-item.active::before { content: ''; position: absolute; left: -8px; top: 8px; bottom: 8px; width: 3px; background-color: var(--accent); border-radius: 3px; }
            .video-name { font-size: 14px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
            .video-details { font-size: 12px; color: var(--text-secondary); }
            .studio-main { flex-grow: 1; display: flex; flex-direction: column; min-width: 0; }
            .main-controls { display: none; align-items: center; padding: 8px; gap: 8px; flex-shrink: 0; border-bottom: 1px solid var(--border); }
            .control-btn { background-color: rgba(255,255,255,0.1); border: 1px solid transparent; color: var(--text-primary); padding: 8px 12px; border-radius: 6px; display: flex; align-items: center; gap: 6px; cursor: pointer; transition: all 0.2s; }
            .control-btn:hover:not(:disabled) { background-color: var(--accent); } .control-btn:disabled { opacity: 0.5; cursor: not-allowed; } .control-btn.recording { background-color: var(--danger); }
            .main-gallery { user-select: none; flex-grow: 1; padding: 10px; overflow-y: auto; display: flex; flex-wrap: wrap; gap: 10px; align-content: flex-start; }
            .gallery-item { cursor: pointer; position: relative; width: 160px; height: 120px; background-color: #000; border-radius: 6px; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end; transition: transform 0.2s ease, opacity 0.2s ease, box-shadow 0.2s ease; }
            .gallery-item.dragging { opacity: 0.4; box-shadow: 0 10px 20px rgba(0,0,0,0.4); transform: scale(1.05); cursor: grabbing; }
            .gallery-item:active { cursor: grabbing; }
            .gallery-item img, .gallery-item video { position: absolute; top: 0; left: 0; width: 100%; height: 100%; object-fit: cover; pointer-events: none; }
            .gallery-label { position: relative; z-index: 1; background: linear-gradient(to top, rgba(0,0,0,0.7), transparent); color: white; font-size: 11px; padding: 4px 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
            .gallery-item-controls { position: absolute; top: 5px; right: 5px; display: flex; gap: 4px; opacity: 0; transition: opacity 0.2s; z-index: 2; pointer-events: none; }
            .gallery-item:hover .gallery-item-controls { opacity: 1; pointer-events: auto; }
            .item-action-btn { width: 24px; height: 24px; background: rgba(0,0,0,0.6); color: #fff; border: none; border-radius: 50%; cursor: pointer; display: flex; align-items: center; justify-content: center; }
            .item-action-btn:hover { background-color: var(--accent); } .delete-item-btn:hover { background-color: var(--danger); }
            .gallery-overlay { position: absolute; inset: 0; background: rgba(0,0,0,0.7); color: white; display: flex; align-items: center; justify-content: center; z-index: 3; font-size: 12px; }
            #z-media-studio-fullscreen { position: fixed; inset: 0; background: rgba(0,0,0,0.9); z-index: 2147483647; display: flex; align-items: center; justify-content: center; opacity: 0; pointer-events: none; transition: opacity 0.3s; }
            #z-media-studio-fullscreen.visible { opacity: 1; pointer-events: auto; }
            #z-media-studio-fullscreen-content { max-width: 90vw; max-height: 90vh; }
            #z-media-studio-fullscreen-content > * { width: 100%; height: 100%; object-fit: contain; }
            svg { width: 1.2em; height: 1.2em; fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
            .empty-list, .empty-gallery { padding: 20px; text-align: center; color: var(--text-secondary); }
        `;
        shadowRoot.appendChild(style);
        const fab = document.createElement('div'); fab.id = 'z-media-studio-fab'; setSafeHTML(fab, ICONS.studio); shadowRoot.appendChild(fab);
        const panel = document.createElement('div'); panel.id = 'z-media-studio-panel';
        setSafeHTML(panel, `<header class="studio-header"><div class="title">Media Studio</div><button class="header-btn" id="z-studio-close-btn" title="Close">${ICONS.close}</button><div class="header-progress-bar"></div></header><div class="studio-content"><aside class="studio-sidebar"><div class="video-list"></div></aside><main class="studio-main"><div class="main-controls"><button class="control-btn" id="z-studio-capture-btn" title="Capture Frame">${ICONS.capture}</button><button class="control-btn" id="z-studio-record-btn" title="Start/Stop Recording">${ICONS.record}</button><button class="control-btn" id="z-studio-extract-btn" title="Start/Stop Extracting">${ICONS.extract}</button></div><div class="main-gallery"></div></main></div>`); shadowRoot.appendChild(panel);
        const fullscreenViewer = document.createElement('div'); fullscreenViewer.id = 'z-media-studio-fullscreen';
        const fullscreenContent = document.createElement('div'); fullscreenContent.id = 'z-media-studio-fullscreen-content'; fullscreenViewer.appendChild(fullscreenContent); shadowRoot.appendChild(fullscreenViewer);
        Object.assign(State.dom, { shadowHost, fab, panel, fullscreenViewer, fullscreenContent, header: panel.querySelector('.studio-header'), headerTitle: panel.querySelector('.title'), headerProgress: panel.querySelector('.header-progress-bar'), videoList: panel.querySelector('.video-list'), controls: panel.querySelector('.main-controls'), captureBtn: panel.querySelector('#z-studio-capture-btn'), recordBtn: panel.querySelector('#z-studio-record-btn'), extractBtn: panel.querySelector('#z-studio-extract-btn'), gallery: panel.querySelector('.main-gallery'), closeBtn: panel.querySelector('#z-studio-close-btn'), });
    }

    function getDragAfterElement(container, y) {
        const draggableElements = [...container.querySelectorAll('.gallery-item:not(.dragging)')];
        return draggableElements.reduce((closest, child) => { const box = child.getBoundingClientRect(); const offset = y - box.top - box.height / 2; if (offset < 0 && offset > closest.offset) { return { offset: offset, element: child }; } else { return closest; } }, { offset: Number.NEGATIVE_INFINITY }).element;
    }
    function onDragStart(event) {
        const itemEl = event.target.closest('.gallery-item');
        if (!itemEl || event.target.closest('.item-action-btn')) return;
        State.dragDropState.isDragging = true;
        State.dragDropState.draggedItemId = parseInt(itemEl.dataset.itemId, 10);
        setTimeout(() => itemEl.classList.add('dragging'), 0);
        const item = State.capturedItems.find(i => i.id === State.dragDropState.draggedItemId);
        if (item) {
            const mime = item.type === 'image' ? 'image/jpeg' : 'video/webm';
            const extension = item.type === 'image' ? 'jpg' : 'webm';
            const fileName = `zstudio-capture-${item.id}.${extension}`;
            event.dataTransfer.setData('DownloadURL', `${mime}:${fileName}:${item.data}`);
            event.dataTransfer.setData('text/plain', item.data);
            const dragImage = itemEl.querySelector('img, video');
            if (dragImage) { event.dataTransfer.setDragImage(dragImage, dragImage.clientWidth / 2, dragImage.clientHeight / 2); }
        }
    }
    function onDragOver(event) {
        event.preventDefault();
        const gallery = State.dom.gallery;
        const afterElement = getDragAfterElement(gallery, event.clientY);
        const draggedElement = gallery.querySelector('.dragging');
        if (!draggedElement) return;
        if (afterElement == null) { gallery.appendChild(draggedElement); } else { gallery.insertBefore(draggedElement, afterElement); }
    }
    function onDrop(event) {
        event.preventDefault();
        const gallery = State.dom.gallery;
        const draggedElement = gallery.querySelector('.dragging');
        if (!draggedElement) return;
        const newElementsOrder = [...gallery.querySelectorAll('.gallery-item')];
        const newItemsOrder = newElementsOrder.map(el => { const id = parseInt(el.dataset.itemId, 10); return State.capturedItems.find(item => item.id === id); }).filter(Boolean);
        State.capturedItems = newItemsOrder;
    }
    function onDragEnd(event) {
        const draggedElement = State.dom.gallery.querySelector('.dragging');
        if (draggedElement) { draggedElement.classList.remove('dragging'); }
        State.dragDropState.isDragging = false;
        State.dragDropState.draggedItemId = null;
    }

    function handleGalleryClick(event) {
        if (State.dragDropState.isDragging) return;
        const itemAction = event.target.closest('.item-action-btn');
        const galleryItem = event.target.closest('.gallery-item');
        if (itemAction && galleryItem) {
             const itemId = parseInt(galleryItem.dataset.itemId, 10);
             if (itemAction.classList.contains('delete-item-btn')) { Actions.deleteCapturedItem(itemId, event); }
             else if (itemAction.classList.contains('download-btn')) { Actions.downloadItem(itemId, event); }
             return;
        }
        if (galleryItem) {
            const itemId = parseInt(galleryItem.dataset.itemId, 10);
            const item = State.capturedItems.find(i => i.id === itemId);
            if (item) Actions.showFullscreen(item);
        }
    }

    function bindEvents() {
        State.dom.fab.addEventListener('click', () => Actions.togglePanel());
        State.dom.closeBtn.addEventListener('click', () => Actions.togglePanel());
        State.dom.header.addEventListener('pointerdown', e => { if (e.target.closest('.header-btn') || !e.isPrimary) return; const target = e.target; target.setPointerCapture(e.pointerId); State.dragInfo = { offsetX: e.clientX - State.dom.panel.getBoundingClientRect().left, offsetY: e.clientY - State.dom.panel.getBoundingClientRect().top }; State.dom.panel.style.userSelect = 'none'; target.addEventListener('pointermove', e => { if (!State.dragInfo) return; const panel = State.dom.panel; panel.style.left = `${e.clientX - State.dragInfo.offsetX}px`; panel.style.top = `${e.clientY - State.dragInfo.offsetY}px`; panel.style.transform = 'none'; }); target.addEventListener('pointerup', e => { if (!State.dragInfo) return; State.dragInfo = null; target.releasePointerCapture(e.pointerId); State.dom.panel.style.userSelect = ''; }, { once: true }); });
        State.dom.videoList.addEventListener('click', e => { const item = e.target.closest('.video-item'); if (item) Actions.selectVideo(parseInt(item.dataset.videoId)); });
        State.dom.captureBtn.addEventListener('click', () => Actions.captureFrame());
        State.dom.recordBtn.addEventListener('click', () => Actions.toggleRecording());
        State.dom.extractBtn.addEventListener('click', () => Actions.toggleExtracting());

        State.dom.gallery.addEventListener('click', handleGalleryClick);
        State.dom.gallery.addEventListener('dragstart', onDragStart);
        State.dom.gallery.addEventListener('dragover', onDragOver);
        State.dom.gallery.addEventListener('drop', onDrop);
        State.dom.gallery.addEventListener('dragend', onDragEnd);

        State.dom.fullscreenViewer.addEventListener('click', () => Actions.hideFullscreen());
        State.dom.fullscreenContent.addEventListener('click', (e) => e.stopPropagation());
        window.ZMediaStudioTeardown = () => { if (State.dom.shadowHost) State.dom.shadowHost.remove(); window.ZMediaStudioInitialized = undefined; };
    }

    function init() { if (document.getElementById('z-media-studio-host')) return; createView(); bindEvents(); }
    if (document.readyState === 'complete') init(); else window.addEventListener('load', init);
})();
'''
;

const zKeyMapper =
'''
if (typeof window.ZKeyMapperInitialized !== 'undefined') {
    if (window.ZKeyMapperTeardown) window.ZKeyMapperTeardown();
}
window.ZKeyMapperInitialized = true;

(function() {
    const STORE_NAME = 'zKeyMapperState';
    const STATE_KEY = 'lastState';

    let debounceTimer = null;
    let inactivityTimer = null;
    const INACTIVITY_DURATION = 3000;
    const MAX_RENDER_LINES = 10;
    let CURRENT_URL = window.location.href;

    const appState = {
        dom: {},
        isEnabled: true,
        rawText: '',
        isDragging: false,
        dragStart: { x: 0, y: 0, initialX: 0, initialY: 0 },
        hasMoved: false,
        position: {
            isDefault: true,
            left: '50%',
            top: 'auto',
            bottom: '5px',
            transform: 'translateX(-50%)'
        }
    };

    const ICONS = {
        settings: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06-.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"></path></svg>`
    };

    let policy;
    try {
        policy = window.trustedTypes.createPolicy('z-keymapper-policy', { createHTML: string => string });
    } catch (e) { policy = null; }

    const setHTML = (element, html) => {
        if (policy) element.innerHTML = policy.createHTML(html);
        else element.innerHTML = html;
    };

    const Persistence = {
        async performTransaction(mode, action) {
            if (!window.ZSharedDB || typeof window.ZSharedDB.performTransaction !== 'function') {
                return Promise.reject(new Error("ZKeyMapper Error: ZSharedDB core is not available."));
            }
            return window.ZSharedDB.performTransaction(STORE_NAME, mode, action);
        },
        async saveState(state) {
            return this.performTransaction('readwrite', store => store.put({ id: STATE_KEY, ...state }));
        },
        async loadState() {
            try {
                return await this.performTransaction('readonly', store => store.get(STATE_KEY));
            } catch (e) {
                return null;
            }
        }
    };

    function generateRandomColor() {
        const hue = (Math.random() * 360);
        const saturation = 80 + Math.random() * 20;
        const lightness = 65 + Math.random() * 10;
        return `hsl(${hue}, ${saturation}%, ${lightness}%)`;
    }
    function getColorForWord(word) {
        const cleanWord = word.trim().toLowerCase();
        if (!cleanWord || !cleanWord.match(/[\p{L}\p{N}]/u)) return null;
        return generateRandomColor();
    }
    function setCursorToEnd(element) {
        if (!element) return;
        element.focus();
        const range = document.createRange();
        const selection = window.getSelection();
        if(selection){
            range.selectNodeContents(element);
            range.collapse(false);
            selection.removeAllRanges();
            selection.addRange(range);
        }
    }
    function enterInactiveMode() {
        if (appState.dom.panelContainer && document.activeElement !== appState.dom.editor) {
            appState.dom.panelContainer.classList.add('inactive');
        }
    }
    function resetInactivityTimer() {
        clearTimeout(inactivityTimer);
        if (appState.dom.panelContainer) {
            appState.dom.panelContainer.classList.remove('inactive');
        }
        if (document.activeElement !== appState.dom.editor) {
            inactivityTimer = setTimeout(enterInactiveMode, INACTIVITY_DURATION);
        }
    }

    function applyPosition() {
        const panel = appState.dom.panelContainer;
        if (!panel) return;

        Object.assign(panel.style, {
            left: appState.position.left,
            top: appState.position.top,
            bottom: appState.position.bottom,
            transform: appState.position.transform
        });

        // Force reflow to get correct dimensions after applying styles
        panel.getBoundingClientRect();

        const rect = panel.getBoundingClientRect();
        const padding = 5;
        let needsCorrection = false;
        let newLeft = rect.left;
        let newTop = rect.top;

        if (rect.right > window.innerWidth - padding) { newLeft = window.innerWidth - rect.width - padding; needsCorrection = true; }
        if (rect.left < padding) { newLeft = padding; needsCorrection = true; }
        if (rect.bottom > window.innerHeight - padding) { newTop = window.innerHeight - rect.height - padding; needsCorrection = true; }
        if (rect.top < padding) { newTop = padding; needsCorrection = true; }

        if (needsCorrection) {
             panel.style.left = `${newLeft}px`;
             panel.style.top = `${newTop}px`;
             panel.style.bottom = 'auto';
             panel.style.transform = 'none';
        }
    }

    function handleWindowResize() {
        applyPosition();
    }

    function handleDragStart(e) {
        e.stopPropagation();
        appState.isDragging = true;
        appState.hasMoved = false;
        resetInactivityTimer();
        const panel = appState.dom.panelContainer;
        const rect = panel.getBoundingClientRect();
        appState.dragStart.initialX = e.clientX;
        appState.dragStart.initialY = e.clientY;
        appState.dragStart.x = e.clientX - rect.left;
        appState.dragStart.y = e.clientY - rect.top;
        panel.style.transition = 'none';
        panel.style.left = `${rect.left}px`;
        panel.style.top = `${rect.top}px`;
        panel.style.transform = 'none';
        panel.style.bottom = 'auto';
        document.addEventListener('mousemove', handleDragMove);
        document.addEventListener('mouseup', handleDragEnd, { once: true });
    }

    function handleDragMove(e) {
        if (!appState.isDragging) return;
        if (!appState.hasMoved && (Math.abs(e.clientX - appState.dragStart.initialX) > 5 || Math.abs(e.clientY - appState.dragStart.initialY) > 5)) {
            appState.hasMoved = true;
        }
        if (appState.hasMoved) {
            const newLeft = e.clientX - appState.dragStart.x;
            const newTop = e.clientY - appState.dragStart.y;
            appState.dom.panelContainer.style.left = `${newLeft}px`;
            appState.dom.panelContainer.style.top = `${newTop}px`;
        }
    }

    // ==============================================================================
    // LOGIC ĐỊNH VỊ THÔNG MINH
    // ==============================================================================
    async function handleDragEnd(e) {
        if (!appState.isDragging) return;
        appState.isDragging = false;
        document.removeEventListener('mousemove', handleDragMove);
        e.stopPropagation();

        if (!appState.hasMoved) {
            handleSettingsClick();
        } else {
            const panel = appState.dom.panelContainer;
            let rect = panel.getBoundingClientRect();
            const padding = 5;

            let finalLeft = Math.max(padding, Math.min(rect.left, window.innerWidth - rect.width - padding));
            let finalTop = Math.max(padding, Math.min(rect.top, window.innerHeight - rect.height - padding));

            appState.position.isDefault = false;
            appState.position.transform = 'none';
            appState.position.left = `${finalLeft}px`;

            // Quyết định lưu 'top' hay 'bottom'
            if (finalTop > window.innerHeight / 2) {
                appState.position.bottom = `${window.innerHeight - finalTop - rect.height}px`;
                appState.position.top = 'auto';
            } else {
                appState.position.top = `${finalTop}px`;
                appState.position.bottom = 'auto';
            }

            // Áp dụng vị trí mới ngay lập tức
            applyPosition();

            await Persistence.saveState({ position: appState.position });
        }

        appState.dom.panelContainer.style.transition = 'opacity 0.4s ease, transform 0.4s ease, visibility 0.4s';
        resetInactivityTimer();
    }

    function updatePlaceholder() {
        const newUrl = window.location.href;
        if (appState.dom.editor && appState.dom.editor.dataset.placeholder !== newUrl) {
            appState.dom.editor.dataset.placeholder = newUrl;
        }
    }

    function handleSettingsClick() {
        resetInactivityTimer();
        const kernelHost = document.getElementById('z-kernel-host');
        if (kernelHost && typeof window.ZKernel_Toggle === 'function') {
            window.ZKernel_Toggle();
            return;
        }
        const settingsPayload = { type: 'ZKeyMapperSettingsRequest', data: {} };
        window.chrome.webview.postMessage(JSON.stringify(settingsPayload));
    }

    function highlightSyntax() {
        if (!appState.isEnabled || !appState.dom.editor) return;
        const editor = appState.dom.editor;
        const selection = window.getSelection();
        let isTextSelected = selection && !selection.isCollapsed;
        const rawText = appState.rawText;
        const lines = rawText.split('\\n');
        const visibleLines = lines.slice(-MAX_RENDER_LINES);
        const textToRender = visibleLines.join('\\n');
        const tokens = textToRender.split(/([^\p{L}\p{N}]+)/u).filter(Boolean);
        let outputHTML = '';
        tokens.forEach(token => {
            if (token === '\\n') { outputHTML += '<br>'; return; }
            const color = getColorForWord(token);
            if (color) {
                outputHTML += `<span class="z-word-tag" style="color:${color};" title="Click to send '${token}'">${token}</span>`;
            } else {
                const escapedToken = token.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                outputHTML += escapedToken;
            }
        });
        setHTML(editor, outputHTML);
        if (!isTextSelected) { setCursorToEnd(editor); }
    }

    function handleSendAllText() {
        const rawText = appState.rawText.trim();
        if (rawText) {
            const payload = { type: 'ZKeyMapperText', data: { text: rawText } };
            window.chrome.webview.postMessage(JSON.stringify(payload));
            appState.rawText = '';
            appState.dom.editor.textContent = '';
            highlightSyntax();
        }
    }

    function handleSendWord(word) {
        if (word) {
            const payload = { type: 'ZKeyMapperWord', data: { word: word } };
            window.chrome.webview.postMessage(JSON.stringify(payload));
        }
    }

    function createView() {
        document.getElementById('z-keymapper-host')?.remove();
        const shadowHost = document.createElement('div');
        shadowHost.id = 'z-keymapper-host';
        document.body.appendChild(shadowHost);
        const shadowRoot = shadowHost.attachShadow({ mode: 'open' });
        const style = document.createElement('style');
        style.textContent = `
            .panel-container {
                position: fixed;
                width: 400px;
                max-width: 33vw;
                max-height: calc(1.5em * 10 + 30px);
                display: flex;
                flex-direction: column;
                z-index: 2147483647;
                padding: 8px;
                font-family: monospace, sans-serif;
                font-size: 16px;
                line-height: 1.5;
                overflow: hidden;
                opacity: 1;
                transition: opacity 0.4s ease, transform 0.4s ease, visibility 0s 0s;
                transform: translateY(0);
                visibility: visible;
                pointer-events: auto;
            }
            .panel-container.inactive {
                opacity: 0;
                transform: translateY(100%);
                visibility: hidden;
                pointer-events: none;
                transition: opacity 0.4s ease, transform 0.4s ease, visibility 0s 0.4s;
            }
            .chat-wrapper {
                display: flex;
                align-items: flex-start;
                gap: 8px;
                background-color: rgba(30, 30, 30, 0.95);
                border: 1px solid #444;
                border-radius: 12px;
                padding: 6px 15px 6px 6px;
                flex-grow: 1;
                cursor: text;
                transition: border-color 0.3s ease, background-color 0.3s ease;
            }
            .editor {
                position: relative;
                flex-grow: 1;
                min-height: 24px;
                outline: none;
                caret-color: white;
                white-space: pre-wrap;
                color: white;
                overflow-y: auto;
                padding: 4px 0;
                max-height: 150px;
                transition: color 0.4s ease, opacity 0.4s ease;
            }
            .editor:empty:not(:focus)::before {
                content: attr(data-placeholder);
                color: rgba(255, 255, 255, 0.4);
                cursor: text;
                pointer-events: none;
                position: absolute;
                top: 4px; left: 0;
                width: 100%;
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
            }
            .editor::-webkit-scrollbar { width: 8px; }
            .editor::-webkit-scrollbar-track { background: transparent; }
            .editor::-webkit-scrollbar-thumb { background-color: rgba(255, 255, 255, 0.2); border-radius: 4px; }
            .z-word-tag {
                cursor: pointer;
                display: inline-block;
                font-weight: bold;
                transition: all 0.15s ease-out;
                border-radius: 4px;
                border: 1px solid transparent;
                outline: 1px solid transparent;
                outline-offset: 1px;
            }
            .z-word-tag:hover {
                background-color: rgba(0, 0, 0, 0.5);
                border: 1px solid rgba(255, 255, 255, 0.7);
                outline: 1px solid rgba(0, 0, 0, 0.8);
            }
            .icon-btn {
                width: 36px;
                height: 36px;
                min-width: 36px;
                min-height: 36px;
                display: flex;
                justify-content: center;
                align-items: center;
                border-radius: 50%;
                color: #f0f0f0;
                transition: all 0.3s ease;
                flex-shrink: 0;
                cursor: pointer;
            }
            .settings-btn {
                color: #0ea5e9;
                cursor: grab;
                align-self: center;
            }
            .settings-btn:active { cursor: grabbing; }
            .settings-btn:hover { background-color: rgba(255,255,255,0.15); }
        `;
        shadowRoot.appendChild(style);
        const panelContainer = document.createElement('div');
        panelContainer.className = 'panel-container';
        setHTML(panelContainer, `<div class="chat-wrapper"><div id="z-keymapper-settings-btn" class="icon-btn settings-btn" title="Drag to move / Click to open Kernel">${ICONS.settings}</div><div class="editor" contenteditable="true" spellcheck="false" data-placeholder="${CURRENT_URL}"></div></div>`);
        shadowRoot.appendChild(panelContainer);
        appState.dom = {
            shadowHost, panelContainer,
            chatWrapper: panelContainer.querySelector('.chat-wrapper'),
            editor: panelContainer.querySelector('.editor'),
            settingsBtn: panelContainer.querySelector('#z-keymapper-settings-btn')
        };
    }

    function bindEvents() {
        const { editor, settingsBtn, chatWrapper } = appState.dom;
        if (settingsBtn) {
            settingsBtn.addEventListener('mousedown', (e) => {
                if (e.button === 0) {
                    e.preventDefault();
                    handleDragStart(e);
                }
            });
        }
        window.addEventListener('resize', handleWindowResize, { passive: true });
        window.addEventListener('popstate', updatePlaceholder);
        const originalPushState = history.pushState;
        history.pushState = function() {
            originalPushState.apply(history, arguments);
            updatePlaceholder();
        };
        const originalReplaceState = history.replaceState;
        history.replaceState = function() {
            originalReplaceState.apply(history, arguments);
            updatePlaceholder();
        };
        editor.addEventListener('input', () => { resetInactivityTimer(); if (!appState.isEnabled) return; appState.rawText = editor.innerText || ''; clearTimeout(debounceTimer); debounceTimer = setTimeout(highlightSyntax, 50); });
        editor.addEventListener('keydown', (e) => {
            resetInactivityTimer(); e.stopPropagation();
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); if (appState.isEnabled) handleSendAllText(); return; }
            if (e.ctrlKey && e.key.toLowerCase() === 'a') { e.preventDefault(); const selection = window.getSelection(); const range = document.createRange(); range.selectNodeContents(editor); if(selection) { selection.removeAllRanges(); selection.addRange(range); } }
        });
        editor.addEventListener('click', (e) => {
            resetInactivityTimer();
            const clickedTag = e.target.closest('.z-word-tag');
            if (clickedTag) { e.preventDefault(); e.stopPropagation(); handleSendWord(clickedTag.textContent); }
            if (e.target === editor) editor.focus();
        });
        editor.addEventListener('focus', () => { clearTimeout(inactivityTimer); appState.dom.panelContainer.classList.remove('inactive'); });
        editor.addEventListener('blur', resetInactivityTimer);
        chatWrapper.addEventListener('click', (e) => { if (!e.target.closest('.icon-btn')) editor.focus(); });
        editor.addEventListener('keyup', (e) => e.stopPropagation());
        editor.addEventListener('keypress', (e) => e.stopPropagation());
        editor.addEventListener('paste', (e) => { resetInactivityTimer(); e.preventDefault(); e.stopPropagation(); const text = e.clipboardData.getData('text/plain'); document.execCommand('insertText', false, text); });
        ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart'].forEach(eventName => {
            document.addEventListener(eventName, resetInactivityTimer, { capture: true, passive: true });
        });
    }

    function enable() { appState.isEnabled = true; if (appState.dom.panelContainer) { appState.dom.panelContainer.style.display = 'flex'; resetInactivityTimer(); } }
    function disable() { appState.isEnabled = false; if (appState.dom.panelContainer) { appState.dom.panelContainer.style.display = 'none'; clearTimeout(inactivityTimer); } }

    window.zkeymapper_toggle = (isEnabled) => isEnabled ? enable() : disable();
    window.ZKeyMapperTeardown = () => {
        if (appState.dom.shadowHost) appState.dom.shadowHost.remove();
        window.removeEventListener('resize', handleWindowResize);
        window.removeEventListener('popstate', updatePlaceholder);
        ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart'].forEach(eventName => {
            document.removeEventListener(eventName, resetInactivityTimer, { capture: true });
        });
        window.ZKeyMapperInitialized = undefined;
    };

    async function init() {
        if (document.getElementById('z-keymapper-host')) return;
        createView();
        bindEvents();
        const savedState = await Persistence.loadState();
        if (savedState && savedState.position) {
            appState.position = savedState.position;
        }
        applyPosition();
        if (appState.dom.panelContainer) {
            enable();
        }
    }

    function main() {
        if (window.ZDB_READY) {
            init();
        } else {
            document.addEventListener('ZDB_READY', init, { once: true });
        }
    }

    if (typeof window.chrome?.webview?.postMessage === "function") {
         if (document.body) {
             main();
         } else {
             document.addEventListener('DOMContentLoaded', main);
         }
    }

})();
'''
;
implementation

end.
