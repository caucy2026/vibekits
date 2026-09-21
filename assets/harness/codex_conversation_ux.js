(() => {
  if (window.__vibekitsConversationUxInstalled) return;
  window.__vibekitsConversationUxInstalled = true;
  let contextSessionRow = null;
  let continuationRelations = [];
  let pendingContinuation = null;
  let activeSessionId = '';
  let publishedSessionId = '';
  let continuationProgress = null;
  let continuationRequestInFlight = false;
  // Official uiWorkspace.selection persists this exact shape (alpha.2).
  window.__vibekitsCurrentSessionId = () => {
    try {
      return JSON.parse(localStorage.getItem('dsh.sessions.current') || '{}').sessionId || '';
    } catch { return ''; }
  };

  const sessionIdForRow = (row) => {
    if (!(row instanceof HTMLElement)) return '';
    const idHost = row.matches('[data-session-id]')
      ? row : row.querySelector('[data-session-id]');
    const explicit = idHost?.getAttribute('data-session-id')?.trim();
    if (explicit) return explicit;
    const href = row.querySelector('a[href]')?.getAttribute('href') || '';
    const match = href.match(/\/sessions?\/([^/?#]+)/i);
    return match ? decodeURIComponent(match[1]) : '';
  };

  const sessionTitleForRow = (row) => {
    if (!(row instanceof HTMLElement)) return '未命名会话';
    const continuationTitle =
      row.dataset.vibekitsContinuationTitle?.trim() || '';
    if (continuationTitle) return continuationTitle;
    const actionLabel = row.querySelector(
      'button[aria-label^="会话“"], button[aria-label^="Session "]',
    )?.getAttribute('aria-label')?.trim() || '';
    const labelledTitle = actionLabel.match(
      /^(?:会话[“"]|Session\s+[“"])(.+?)(?:[”"](?:的操作|\s+actions?)?)$/i,
    )?.[1]?.trim();
    if (labelledTitle) return labelledTitle;
    const clone = row.cloneNode(true);
    clone.querySelectorAll('button, time').forEach((node) => node.remove());
    return (clone.textContent?.trim().replace(/\s+/g, ' ') || '未命名会话')
      .replace(/\s*(刚刚|\d+\s*(秒|分钟|小时|天|周|个月|月|年)(前)?)$/, '')
      .trim();
  };

  const replaceMenuItemLabel = (item, label) => {
    const textNodes = [];
    const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.textContent?.trim()) textNodes.push(node);
    }
    const labelNode = textNodes.at(-1);
    if (labelNode) {
      labelNode.textContent = label;
    } else {
      const span = document.createElement('span');
      span.textContent = label;
      item.appendChild(span);
    }
  };

  const replaceNewSessionIcon = (item) => {
    const icon = item.querySelector('svg');
    if (!(icon instanceof SVGElement)) return;
    icon.replaceChildren();
    for (const d of [
      'M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h6',
      'M16 3v6',
      'M13 6h6',
    ]) {
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', d);
      path.setAttribute('fill', 'none');
      path.setAttribute('stroke', 'currentColor');
      path.setAttribute('stroke-linecap', 'round');
      path.setAttribute('stroke-linejoin', 'round');
      icon.appendChild(path);
    }
  };

  const replaceDeleteSessionIcon = (item) => {
    const icon = item.querySelector('svg');
    if (!(icon instanceof SVGElement)) return;
    icon.replaceChildren();
    for (const d of [
      'M3 6h18',
      'M8 6V4h8v2',
      'M19 6l-1 14H6L5 6',
      'M10 11v5',
      'M14 11v5',
    ]) {
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', d);
      path.setAttribute('fill', 'none');
      path.setAttribute('stroke', 'currentColor');
      path.setAttribute('stroke-linecap', 'round');
      path.setAttribute('stroke-linejoin', 'round');
      icon.appendChild(path);
    }
  };

  const requestContinuationFromMenu = (item) => {
    if (continuationRequestInFlight) return;
    continuationRequestInFlight = true;
    const row = contextSessionRow;
    const sourceSessionId = sessionIdForRow(row);
    const sourceTitle = sessionTitleForRow(row);
    const request = {
      type: 'vibekits.continueSession',
      sessionId: sourceSessionId,
      title: sourceTitle,
    };
    window.__vibekitsLastContinuationRequest = request;
    // Hand the request to the host before any optional UI decoration. A
    // rendering failure must never leave a visible menu action that does no
    // work or a permanently latched in-flight flag.
    postHostMessage(request);
    try {
      window.__vibekitsSetContinuationProgress?.(
        '正在创建派生会话…', false, [sourceSessionId],
      );
      item.setAttribute('aria-busy', 'true');
      item.setAttribute('aria-disabled', 'true');
      replaceMenuItemLabel(item, '正在创建…');
      // Let the official menu close its own React state and restore focus.
      document.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Escape', code: 'Escape', bubbles: true,
      }));
    } catch {
      // The host request is already running and will publish scoped progress.
    }
  };

  const requestDeleteFromMenu = () => {
    const row = contextSessionRow;
    const rowTitle = sessionTitleForRow(row);
    const relation = continuationRelations.find((item) =>
      item.continuationTitleSnapshot === rowTitle,
    );
    // Official alpha.2 sidebar rows often omit their id. Never substitute the
    // persisted "current" id here: after opening a derived blank session that
    // value can lag behind the selected row and delete the source instead.
    // An empty id is resolved by the host against the clicked row's title.
    const sessionId = relation?.continuationSessionId || sessionIdForRow(row);
    const request = {
      type: 'vibekits.deleteSession',
      sessionId,
      title: relation?.continuationTitleSnapshot || rowTitle,
      isCurrent: sessionId === window.__vibekitsCurrentSessionId(),
    };
    postHostMessage(request);
    try {
      document.dispatchEvent(new KeyboardEvent('keydown', {
        key: 'Escape', code: 'Escape', bubbles: true,
      }));
    } catch {
      // The host confirmation remains authoritative if menu cleanup fails.
    }
  };

  const decorateSessionContextMenu = () => {
    if (!(contextSessionRow instanceof HTMLElement)) return;
    const menus = [...document.querySelectorAll('[role="menu"]')].filter(
      (menu) => menu instanceof HTMLElement && menu.offsetParent !== null,
    );
    const archiveAction = [...document.querySelectorAll(
      'button, [role="menuitem"], [data-radix-collection-item]',
    )].find((element) => {
      if (!(element instanceof HTMLElement) || element.offsetParent === null) {
        return false;
      }
      const label = element.textContent?.trim() || '';
      return label === '归档会话' || label === 'Archive session';
    });
    const menu = menus.at(-1) ?? archiveAction?.parentElement;
    if (!(menu instanceof HTMLElement)) return;
    // Older builds appended one same-labelled row for every child relation.
    // Remove those stale rows and keep exactly one creation action. Navigation
    // between source and child belongs in the in-conversation source card.
    for (const stale of menu.querySelectorAll(
      '.vibekits-child-session-menu-item',
    )) stale.remove();
    const existingActions = [...menu.querySelectorAll(
      '.vibekits-continue-session-menu-item',
    )];
    const existingDeleteActions = [...menu.querySelectorAll(
      '.vibekits-delete-session-menu-item',
    )];
    for (const duplicate of existingActions.slice(1)) duplicate.remove();
    for (const duplicate of existingDeleteActions.slice(1)) duplicate.remove();
    if (existingActions.length > 0 || existingDeleteActions.length > 0) return;
    const template = archiveAction ??
      menu.querySelector('[role="menuitem"], button');
    const item = template instanceof HTMLElement
      ? template.cloneNode(true)
      : document.createElement('button');
    item.type = 'button';
    item.className = `${template?.className || ''} vibekits-continue-session-menu-item`;
    item.setAttribute('role', 'menuitem');
    item.setAttribute('aria-label', '派生会话');
    item.title = '压缩当前会话上下文并创建派生会话继续开发';
    replaceMenuItemLabel(item, '派生会话');
    replaceNewSessionIcon(item);
    menu.appendChild(item);

    const deleteItem = template instanceof HTMLElement
      ? template.cloneNode(true)
      : document.createElement('button');
    deleteItem.type = 'button';
    deleteItem.className = `${template?.className || ''} vibekits-delete-session-menu-item`;
    deleteItem.setAttribute('role', 'menuitem');
    deleteItem.setAttribute('aria-label', '删除会话');
    deleteItem.title = '永久删除此会话的聊天、推理和工具调用记录';
    replaceMenuItemLabel(deleteItem, '删除会话');
    replaceDeleteSessionIcon(deleteItem);
    menu.appendChild(deleteItem);
    requestAnimationFrame(() => {
      const continuationRect = item.getBoundingClientRect();
      const deleteRect = deleteItem.getBoundingClientRect();
      postHostMessage({
        type: 'vibekits.sessionMenuGeometry',
        continuation: {
          left: continuationRect.left,
          top: continuationRect.top,
          width: continuationRect.width,
          height: continuationRect.height,
        },
        delete: {
          left: deleteRect.left,
          top: deleteRect.top,
          width: deleteRect.width,
          height: deleteRect.height,
        },
      });
    });
  };

  if (!window.__vibekitsSessionContextMenuInstalled) {
    window.__vibekitsSessionContextMenuInstalled = true;
    // React may reconcile a portal menu after it has been decorated. A
    // delegated capture handler keeps VibeKits actions functional even when
    // React preserves/clones the injected menu row without its node listener.
    document.addEventListener('click', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      const continuationItem = target?.closest(
        '.vibekits-continue-session-menu-item',
      );
      const deleteItem = target?.closest('.vibekits-delete-session-menu-item');
      if (!(continuationItem instanceof HTMLElement) &&
          !(deleteItem instanceof HTMLElement)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (continuationItem instanceof HTMLElement) {
        requestContinuationFromMenu(continuationItem);
      } else {
        requestDeleteFromMenu();
      }
    }, true);
    window.addEventListener('contextmenu', (event) => {
      const rowsAtPointer = visibleSessionRows().filter((candidate) => {
        const rect = candidate.getBoundingClientRect();
        return event.clientX >= rect.left && event.clientX <= rect.right &&
          event.clientY >= rect.top && event.clientY <= rect.bottom;
      }).sort((left, right) => {
        const a = left.getBoundingClientRect();
        const b = right.getBoundingClientRect();
        return (a.width * a.height) - (b.width * b.height);
      });
      let row = rowsAtPointer[0] ||
        (event.target instanceof Element
          ? event.target.closest('[role="treeitem"]') : null);
      if (!(row instanceof HTMLElement)) return;
      const actionRow = row.classList.contains(
        'vibekits-synthetic-continuation-row',
      ) ? visibleSessionRows().find((candidate) =>
        !candidate.classList.contains('vibekits-synthetic-continuation-row') &&
        (sessionIdForRow(candidate) === row.dataset.sourceSessionId ||
          sessionTitleForRow(candidate) === row.dataset.sourceTitle),
      ) : row;
      const action = actionRow?.querySelector(
        'button[aria-label^="会话“"], button[aria-label^="Session "]',
      );
      if (!(action instanceof HTMLElement)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      contextSessionRow = actionRow;
      action.click();
      window.setTimeout(decorateSessionContextMenu, 30);
    }, true);
  }

  const markSelectedSessionActions = () => {
    for (const marked of document.querySelectorAll(
      '.vibekits-selected-session-actions, .vibekits-selected-session-time',
    )) {
      marked.classList.remove(
        'vibekits-selected-session-actions',
        'vibekits-selected-session-time',
      );
    }
    for (const row of document.querySelectorAll(
      '[role="treeitem"][aria-selected="true"]',
    )) {
      if (!(row instanceof HTMLElement)) continue;
      const directSpans = [...row.children].filter(
        (child) => child instanceof HTMLSpanElement,
      );
      const actions = directSpans.find(
        (span) => span.querySelector('button[aria-label]') !== null,
      );
      if (!(actions instanceof HTMLSpanElement)) continue;
      actions.classList.add('vibekits-selected-session-actions');
      const time = actions.previousElementSibling;
      if (time instanceof HTMLSpanElement) {
        time.classList.add('vibekits-selected-session-time');
      }
    }
  };

  const localizeOfficialActions = () => {
    for (const element of document.querySelectorAll('button, [role="button"]')) {
      if (element.textContent?.trim() !== 'Session log') continue;
      const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
      let node = walker.nextNode();
      while (node) {
        if (node.textContent?.includes('Session log')) {
          node.textContent = node.textContent.replace('Session log', '导出会话日志');
        }
        node = walker.nextNode();
      }
      element.setAttribute('title', '导出当前会话的完整日志');
      element.setAttribute('aria-label', '导出会话日志');
    }
  };

  const publishInferenceErrors = () => {
    const published = window.__vibekitsInferenceErrorSignatures ||= new Set();
    for (const status of document.querySelectorAll('[role="status"]')) {
      if (!(status instanceof HTMLElement)) continue;
      const code = [...status.querySelectorAll('code')]
        .map((element) => element.textContent?.trim() || '')
        .find((value) => value === 'AUTH');
      if (!code) continue;
      const message = status.textContent?.replace(code, '').trim() || '';
      const signature = `${code}:${message}`;
      if (published.has(signature)) continue;
      published.add(signature);
      const payload = JSON.stringify({
        type: 'vibekits.inferenceError',
        code,
        message,
      });
      if (window.chrome?.webview?.postMessage) {
        window.chrome.webview.postMessage(payload);
      } else if (window.VibekitsHost?.postMessage) {
        window.VibekitsHost.postMessage(payload);
      }
    }
  };

  const styleId = 'vibekits-codex-conversation-ux';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      [data-conversation-scroll] {
        --dsh-content-font-size: 14px;
        --dsh-content-font-size-secondary: 13px;
        overscroll-behavior: contain;
        touch-action: pan-y;
      }

      /* Match the native text-field affordance over the whole editable area.
         Buttons in the composer keep their own pointer cursor. */
      [data-composer-card] [data-input-scroll],
      [data-composer-card] [data-input-scroll] [contenteditable="true"] {
        cursor: text !important;
      }

      /* Keep the primary answer comfortably readable. Process details remain
         secondary and folded by the official Harness disclosure widgets. */
      [data-conversation-scroll] [data-chat-flow] [data-chat-anchor-key],
      [data-conversation-scroll] [data-chat-flow] p,
      [data-conversation-scroll] [data-chat-flow] li,
      [data-conversation-scroll] [data-chat-flow] blockquote {
        font-size: var(--dsh-content-font-size) !important;
        line-height: 22px !important;
      }

      [data-conversation-scroll] [data-chat-flow] h1 {
        font-size: 16px !important;
        line-height: 23px !important;
      }

      [data-conversation-scroll] [data-chat-flow] h2 {
        font-size: 15px !important;
        line-height: 22px !important;
      }

      [data-conversation-scroll] [data-chat-flow] h3 {
        font-size: 13px !important;
        line-height: 20px !important;
      }

      [data-conversation-scroll] [data-chat-flow] summary,
      [data-conversation-scroll] [data-chat-flow] details > div {
        font-size: var(--dsh-content-font-size-secondary) !important;
        line-height: 20px !important;
      }

      [data-conversation-scroll] [data-chat-flow] pre,
      [data-conversation-scroll] [data-chat-flow] code {
        font-size: 12.5px !important;
        line-height: 19px !important;
      }

      #vibekits-scroll-to-latest {
        position: fixed;
        left: 50%;
        bottom: 92px;
        z-index: 2147483000;
        width: 34px;
        height: 34px;
        padding: 0;
        border: 1px solid color-mix(in srgb, rgba(120, 120, 120, 0.22) 82%, #b98223 18%);
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.96);
        color: color-mix(in srgb, rgba(45, 45, 45, 0.76) 80%, #b98223 20%);
        box-shadow: 0 5px 18px rgba(0, 0, 0, 0.14);
        font: 500 22px/30px system-ui, sans-serif;
        cursor: pointer;
        transform: translate(-50%, 8px) scale(0.92);
        opacity: 0;
        pointer-events: none;
        transition: opacity 140ms ease, transform 140ms ease,
          background-color 140ms ease;
      }

      #vibekits-scroll-to-latest[data-visible="true"] {
        opacity: 1;
        pointer-events: auto;
        transform: translate(-50%, 0) scale(1);
      }

      #vibekits-scroll-to-latest:hover {
        background: #fff;
      }

      #vibekits-scroll-to-latest:focus-visible {
        outline: 2px solid color-mix(in srgb, var(--dsw-alias-label-primary) 76%, #b98223 24%);
        outline-offset: 2px;
      }

      /* The selected session keeps its action visible. Other rows retain the
         official hover-only action and can show their running status dot. */
      .vibekits-selected-session-actions {
        display: inline-flex !important;
      }

      .vibekits-selected-session-time {
        display: none !important;
      }

      /* Keep official typography, spacing and controls. VibeKits-owned
         Harness actions add only a restrained warm-yellow tint. */
      .vibekits-continue-session-menu-item,
      .vibekits-delete-session-menu-item,
      .vibekits-child-session-menu-item {
        color: var(--dsw-alias-label-primary) !important;
        color: color-mix(in srgb, var(--dsw-alias-label-primary) 78%, #b98223 22%) !important;
      }

      .vibekits-continue-session-menu-item svg,
      .vibekits-delete-session-menu-item svg,
      .vibekits-child-session-menu-item svg {
        color: inherit !important;
        stroke: currentColor !important;
      }

      .vibekits-continue-session-menu-item:hover,
      .vibekits-delete-session-menu-item:hover,
      .vibekits-child-session-menu-item:hover {
        background: color-mix(in srgb, var(--dsw-alias-interactive-bg-hover) 90%, #b98223 10%) !important;
      }

      .vibekits-continuation-source-card {
        display: block;
        margin: 10px auto 4px;
        padding: 7px 12px;
        border: 1px solid color-mix(in srgb, var(--dsw-alias-border-l1) 80%, #b98223 20%);
        border-radius: 9px;
        background: color-mix(in srgb, var(--dsw-specific-input-major) 92%, #b98223 8%);
        color: color-mix(in srgb, var(--dsw-alias-label-primary) 78%, #b98223 22%);
        font: 500 12px/18px system-ui, sans-serif;
        cursor: pointer;
      }

      .vibekits-continuation-source-card:disabled {
        cursor: default;
        opacity: 0.62;
      }

      .vibekits-continuation-source-card.is-empty-session {
        position: fixed;
        z-index: 1200;
        margin: 0;
      }

      .vibekits-synthetic-continuation-row {
        color: color-mix(in srgb, var(--dsw-alias-label-primary) 88%, #b98223 12%);
      }

      .vibekits-synthetic-session-state {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        margin-left: 6px;
        color: color-mix(in srgb, var(--dsw-alias-label-secondary) 82%, #b98223 18%);
        font: 500 11px/16px system-ui, sans-serif;
      }

      .vibekits-synthetic-session-state::before {
        content: '';
        width: 9px;
        height: 9px;
        border: 1.5px solid color-mix(in srgb, var(--dsw-alias-label-primary) 12%, transparent);
        border-top-color: color-mix(in srgb, var(--dsw-alias-label-primary) 62%, #b98223 38%);
        border-radius: 50%;
        animation: vibekits-continuation-spin .8s linear infinite;
      }

      .vibekits-continuation-progress {
        display: flex; align-items: center; gap: 10px;
        position: fixed; z-index: 1200; margin: 0; padding: 9px 13px;
        border: 1px solid color-mix(in srgb, var(--dsw-alias-border-l1) 78%, #b98223 22%);
        border-radius: 9px;
        background: color-mix(in srgb, var(--dsw-specific-input-major) 90%, #b98223 10%);
        color: color-mix(in srgb, var(--dsw-alias-label-primary) 82%, #b98223 18%);
        font: 500 12px/18px system-ui, sans-serif;
      }

      .vibekits-continuation-spinner {
        width: 14px; height: 14px; flex: 0 0 auto; border-radius: 50%;
        border: 2px solid color-mix(in srgb, var(--dsw-alias-label-primary) 8%, transparent);
        border-top-color: color-mix(in srgb, var(--dsw-alias-label-primary) 58%, #b98223 42%);
        animation: vibekits-continuation-spin .8s linear infinite;
      }

      .vibekits-continuation-progress.is-error .vibekits-continuation-spinner {
        animation: none; border-color: #c2413b; border-radius: 3px;
      }

      .vibekits-continuation-retry {
        margin-left: 8px; padding: 3px 9px; border: 1px solid currentColor;
        border-radius: 6px; background: transparent; color: inherit;
        font: inherit; cursor: pointer;
        color: color-mix(in srgb, var(--dsw-alias-label-primary) 78%, #b98223 22%);
      }

      @supports not (color: color-mix(in srgb, black, white)) {
        #vibekits-scroll-to-latest,
        .vibekits-continue-session-menu-item,
        .vibekits-delete-session-menu-item,
        .vibekits-child-session-menu-item,
        .vibekits-continuation-source-card,
        .vibekits-continuation-progress,
        .vibekits-continuation-retry { color: #74654a !important; }
      }

      @keyframes vibekits-continuation-spin { to { transform: rotate(360deg); } }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  localizeOfficialActions();

  const publishWorkspaceSnapshot = () => {
    const workspaces = [];
    for (const row of document.querySelectorAll(
      '[role="treeitem"][aria-expanded]',
    )) {
      if (!(row instanceof HTMLElement)) continue;
      const labelHost = row.children.item(2);
      const label = labelHost?.textContent?.trim() || '';
      if (!label) continue;
      let section = row.parentElement;
      let active = false;
      for (let depth = 0; section && depth < 6; depth += 1) {
        if (section.querySelector(
          '[role="treeitem"][aria-selected="true"]',
        )) {
          active = true;
          break;
        }
        section = section.parentElement;
      }
      workspaces.push({
        workspaceRef: `dsh-workspace:${label}`,
        label,
        active,
      });
    }
    const signature = JSON.stringify(workspaces);
    if (!workspaces.length || signature === window.__vibekitsWorkspaceSignature) {
      return;
    }
    window.__vibekitsWorkspaceSignature = signature;
    const message = JSON.stringify({
      type: 'vibekits.workspaceSnapshot',
      workspaces,
    });
    if (window.chrome?.webview?.postMessage) {
      window.chrome.webview.postMessage(message);
    } else if (window.VibekitsHost?.postMessage) {
      window.VibekitsHost.postMessage(message);
    }
  };

  if (!window.__vibekitsWorkspaceObserverInstalled) {
    window.__vibekitsWorkspaceObserverInstalled = true;
    let workspaceTimer = 0;
    const scheduleWorkspaceSnapshot = () => {
      clearTimeout(workspaceTimer);
      workspaceTimer = setTimeout(publishWorkspaceSnapshot, 80);
    };
    const workspaceObserver = new MutationObserver(scheduleWorkspaceSnapshot);
    workspaceObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['aria-expanded', 'aria-selected'],
      childList: true,
      characterData: true,
      subtree: true,
    });
  }
  publishWorkspaceSnapshot();
  if (!window.__vibekitsConversationLocalizationInstalled) {
    window.__vibekitsConversationLocalizationInstalled = true;
    const observer = new MutationObserver(() => {
      localizeOfficialActions();
      markSelectedSessionActions();
      publishInferenceErrors();
      decorateSessionContextMenu();
      decorateContinuationTitles();
      renderSyntheticContinuationRows();
      renderContinuationCard();
      publishSelectedSession();
      window.__vibekitsRenderContinuationProgress?.();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
  markSelectedSessionActions();
  publishInferenceErrors();

  const postHostMessage = (payload) => {
    const message = JSON.stringify(payload);
    if (window.chrome?.webview?.postMessage) {
      window.chrome.webview.postMessage(message);
    } else if (window.VibekitsHost?.postMessage) {
      window.VibekitsHost.postMessage(message);
    }
  };

  const publishSelectedSession = () => {
    const sessionId = window.__vibekitsCurrentSessionId();
    if (!sessionId || sessionId === publishedSessionId) return;
    publishedSessionId = sessionId;
    postHostMessage({type: 'vibekits.sessionSelection', sessionId});
  };
  requestAnimationFrame(publishSelectedSession);

  const openThroughOfficialWorkspace = (sessionId) => {
    const probe = visibleSessionRows().find((row) =>
      !row.classList.contains('vibekits-synthetic-continuation-row'),
    );
    if (!(probe instanceof HTMLElement)) return false;
    const fiberKey = Object.getOwnPropertyNames(probe).find((key) =>
      key.startsWith('__reactFiber$'),
    );
    let fiber = fiberKey ? probe[fiberKey] : null;
    for (let depth = 0; fiber && depth < 40; depth += 1) {
      for (const props of [fiber.memoizedProps, fiber.pendingProps]) {
        if (props && typeof props.open === 'function') {
          try {
            props.open(sessionId);
            requestAnimationFrame(() => requestAnimationFrame(() => {
              focusVisibleComposer();
            }));
            return true;
          } catch {
            // Continue through owner fibers; a nearer callback may be scoped.
          }
        }
      }
      fiber = fiber.return;
    }
    return false;
  };

  window.__vibekitsOpenSession = (sessionId) => {
    const row = visibleSessionRows().find(
      (candidate) => sessionIdForRow(candidate) === sessionId,
    );
    if (!(row instanceof HTMLElement)) {
      return /^session-[0-9a-f-]{36}$/.test(sessionId || '') &&
        openThroughOfficialWorkspace(sessionId);
    }
    if (row.classList.contains('vibekits-synthetic-continuation-row')) {
      return openThroughOfficialWorkspace(sessionId);
    }
    const target = row.querySelector(
      'a[href], [role="link"], [data-session-id]',
    ) ?? row;
    target.click();
    requestAnimationFrame(() => requestAnimationFrame(focusVisibleComposer));
    return true;
  };

  window.__vibekitsSelectVisibleSession = (sessionId) => {
    const row = visibleSessionRows().find(
      (candidate) => sessionIdForRow(candidate) === sessionId,
    );
    if (!(row instanceof HTMLElement)) return false;
    if (row.classList.contains('vibekits-synthetic-continuation-row')) {
      return openThroughOfficialWorkspace(sessionId);
    }
    const target = row.querySelector(
      'a[href], [role="link"], [data-session-id]',
    ) ?? row;
    target.click();
    requestAnimationFrame(() => requestAnimationFrame(() => {
      window.__vibekitsRenderContinuationProgress?.();
      focusVisibleComposer();
    }));
    return true;
  };

  window.__vibekitsOpenSessionByTitle = (title) => {
    const wanted = String(title || '').trim();
    const rows = [...document.querySelectorAll(
      '[role="treeitem"]:not([aria-expanded])',
    )].filter((candidate) => candidate instanceof HTMLElement);
    const row = rows.find(
      (candidate) => sessionTitleForRow(candidate) === wanted,
    );
    if (!(row instanceof HTMLElement)) {
      const expand = [...document.querySelectorAll('button')].find((button) =>
        button instanceof HTMLElement && button.offsetParent !== null &&
        /^(展开其余|Show .*more)/i.test(button.textContent?.trim() || ''),
      );
      expand?.click();
      const anchor = document.querySelector(
        '[role="treeitem"][aria-selected="true"]',
      ) ?? expand;
      let scroller = anchor?.parentElement;
      for (let depth = 0; scroller && depth < 8; depth += 1) {
        if (scroller.scrollHeight > scroller.clientHeight) {
          scroller.scrollTop = 0;
        }
        scroller = scroller.parentElement;
      }
      return false;
    }
    (row.querySelector('a[href], [role="link"], [data-session-id]') ?? row)
      .click();
    const search = document.querySelector(
      'input[placeholder*="搜索会话"], input[placeholder*="Search"]',
    );
    if (search instanceof HTMLInputElement && search.value) {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype, 'value',
      )?.set;
      setter?.call(search, '');
      search.dispatchEvent(new Event('input', { bubbles: true }));
    }
    requestAnimationFrame(() => requestAnimationFrame(focusVisibleComposer));
    return true;
  };

  window.__vibekitsOpenNewestEmptySession = () => {
    const globalNewSession = [...document.querySelectorAll('button')].find(
      (candidate) => candidate instanceof HTMLElement &&
        candidate.offsetParent !== null &&
        /^(?:新建会话|New session)$/i.test(
          (candidate.getAttribute('aria-label') || '').trim(),
        ),
    );
    const projectRows = [...document.querySelectorAll(
      '[role="treeitem"][aria-expanded]',
    )].filter((row) => row instanceof HTMLElement);
    const sourceRow = contextSessionRow instanceof HTMLElement
      ? contextSessionRow : document.querySelector(
        '[role="treeitem"][aria-selected="true"]',
      );
    const sourceProject = sourceRow instanceof HTMLElement
      ? projectRows.filter((row) =>
        Boolean(row.compareDocumentPosition(sourceRow) &
          Node.DOCUMENT_POSITION_FOLLOWING),
      ).at(-1)
      : null;
    const candidates = sourceProject instanceof HTMLElement
      ? [...sourceProject.querySelectorAll('button')]
      : [...document.querySelectorAll('button')];
    const button = globalNewSession ?? candidates.find((candidate) =>
      candidate instanceof HTMLElement && (() => {
        const aria = (candidate.getAttribute('aria-label') || '')
          .trim().replace(/\s+/g, ' ');
        if (/(?:新建会话|New session in)/i.test(aria)) return true;
        if (candidate.offsetParent === null) return false;
        const label = (candidate.getAttribute('title') ||
          candidate.textContent || '').trim().replace(/\s+/g, ' ');
        return /^(?:新会话|新建会话|New session)$/i.test(label);
      })(),
    );
    if (!(button instanceof HTMLElement)) return false;
    button.click();
    requestAnimationFrame(() => requestAnimationFrame(() => {
      focusVisibleComposer();
    }));
    return true;
  };

  window.__vibekitsOpenOnlyVisibleBlankSession = () => {
    const blanks = visibleSessionRows().filter((row) =>
      /^(?:新会话|New Session)$/i.test(sessionTitleForRow(row)),
    );
    if (blanks.length !== 1) return false;
    const row = blanks[0];
    (row.querySelector('a[href], [role="link"], [data-session-id]') ?? row)
      .click();
    requestAnimationFrame(() => requestAnimationFrame(focusVisibleComposer));
    return true;
  };

  window.__vibekitsRenderContinuationProgress = () => {
    let card = document.getElementById('vibekits-continuation-progress');
    const current = window.__vibekitsCurrentSessionId();
    const selected = document.querySelector(
      '[role="treeitem"][aria-selected="true"]',
    );
    const currentTitle = sessionTitleForRow(selected);
    const sourceSelected = continuationRequestInFlight &&
      selected instanceof HTMLElement && selected === contextSessionRow;
    if (!continuationProgress ||
        (!sourceSelected &&
         !continuationProgress.sessionIds.includes(current) &&
         !continuationProgress.sessionTitles.includes(currentTitle))) {
      card?.remove();
      return;
    }
    const composer = [...document.querySelectorAll('[data-composer-card]')]
      .find((element) => element instanceof HTMLElement &&
        element.offsetParent !== null);
    const composerInput = [...document.querySelectorAll(
      'textarea, [contenteditable="true"]',
    )].find((element) => element instanceof HTMLElement &&
      element.offsetParent !== null);
    const composerAnchor = composer instanceof HTMLElement
      ? composer : composerInput;
    const host = findConversationHost();
    // A brand-new official session has no conversation scroll surface yet.
    // Its composer is already real and visible, so anchor progress there.
    if (!(host instanceof HTMLElement) &&
        !(composerAnchor instanceof HTMLElement)) {
      return;
    }
    if (!(card instanceof HTMLElement)) {
      card = document.createElement('div');
      card.id = 'vibekits-continuation-progress';
      card.className = 'vibekits-continuation-progress';
      const spinner = document.createElement('span');
      spinner.className = 'vibekits-continuation-spinner';
      const label = document.createElement('span');
      label.className = 'vibekits-continuation-progress-label';
      card.append(spinner, label);
    }
    if (card.parentElement !== document.body) document.body.appendChild(card);
    const anchorRect = composerAnchor instanceof HTMLElement
      ? composerAnchor.getBoundingClientRect() : host.getBoundingClientRect();
    card.style.left = `${Math.max(8, anchorRect.left)}px`;
    card.style.top = `${Math.max(8, anchorRect.top - 44)}px`;
    card.style.maxWidth = `${Math.max(220, anchorRect.width)}px`;
    card.querySelector('.vibekits-continuation-progress-label').textContent =
      continuationProgress.status;
    card.classList.remove('is-error');
    card.querySelector('.vibekits-continuation-retry')?.remove();
  };

  window.__vibekitsSetContinuationProgress = (
    status, done = false, sessionIds = [], sessionTitles = [],
  ) => {
    if (done) {
      continuationProgress = null;
      continuationRequestInFlight = false;
      sessionStorage.removeItem('vibekits.continuation.progress');
    } else {
      const normalizedTitles = [...new Set(
        (Array.isArray(sessionTitles) ? sessionTitles : [])
          .map(String).filter(Boolean),
      )];
      continuationProgress = {
        status: String(status || '正在整理上下文…'),
        sessionIds: [...new Set((Array.isArray(sessionIds) ? sessionIds : [])
          .map(String).filter(Boolean))],
        sessionTitles: normalizedTitles.length > 0
          ? normalizedTitles
          : (continuationProgress?.sessionTitles || []),
      };
      sessionStorage.setItem(
        'vibekits.continuation.progress', JSON.stringify(continuationProgress),
      );
    }
    window.__vibekitsRenderContinuationProgress();
  };

  window.__vibekitsSetContinuationError = (message, retryPayload) => {
    continuationRequestInFlight = false;
    const ids = continuationProgress?.sessionIds?.length
      ? continuationProgress.sessionIds
      : [window.__vibekitsCurrentSessionId()].filter(Boolean);
    window.__vibekitsSetContinuationProgress?.(message, false, ids);
    const card = document.getElementById('vibekits-continuation-progress');
    if (!(card instanceof HTMLElement)) return;
    card.classList.add('is-error');
    let retry = card.querySelector('.vibekits-continuation-retry');
    if (!(retry instanceof HTMLButtonElement)) {
      retry = document.createElement('button');
      retry.type = 'button';
      retry.className = 'vibekits-continuation-retry';
      retry.textContent = '重试';
      card.appendChild(retry);
    }
    retry.onclick = () => {
      retry.disabled = true;
      window.__vibekitsSetContinuationProgress?.('正在重新整理…', false, ids);
      postHostMessage({
        ...(retryPayload || window.__vibekitsLastContinuationRequest || {}),
        type: 'vibekits.continueSession',
      });
    };
  };

  const renderContinuationCard = () => {
    const existing = document.getElementById(
      'vibekits-continuation-source-card',
    );
    const selected = document.querySelector(
      '[role="treeitem"][aria-selected="true"]',
    );
    const currentId = window.__vibekitsCurrentSessionId() || sessionIdForRow(selected) || activeSessionId;
    const currentTitle = sessionTitleForRow(selected);
    const relation = continuationRelations.find(
      (item) => item.continuationSessionId === currentId ||
        currentTitle.startsWith(`${item.sourceTitleSnapshot} `),
    );
    if (!relation) {
      existing?.remove();
      return;
    }
    const host = findConversationHost();
    const composer = [...document.querySelectorAll('[data-composer-card]')]
      .find((element) => element instanceof HTMLElement &&
        element.offsetParent !== null);
    if (!(host instanceof HTMLElement) && !(composer instanceof HTMLElement)) {
      return;
    }
    const sourceExists = relation.sourceAvailable ?? visibleSessionRows().some(
      (row) => sessionIdForRow(row) === relation.sourceSessionId ||
        sessionTitleForRow(row) === relation.sourceTitleSnapshot,
    );
    const text = sourceExists
      ? `派生自《${relation.sourceTitleSnapshot}》`
      : `来源会话已删除：《${relation.sourceTitleSnapshot}》`;
    if (existing instanceof HTMLButtonElement) {
      if (host instanceof HTMLElement) {
        if (existing.parentElement !== host) host.prepend(existing);
        existing.classList.remove('is-empty-session');
        existing.style.removeProperty('left');
        existing.style.removeProperty('top');
        existing.style.removeProperty('max-width');
      } else if (composer instanceof HTMLElement) {
        if (existing.parentElement !== document.body) {
          document.body.appendChild(existing);
        }
        const rect = composer.getBoundingClientRect();
        existing.classList.add('is-empty-session');
        existing.style.left = `${Math.max(8, rect.left)}px`;
        existing.style.top = `${Math.max(8, rect.top - 82)}px`;
        existing.style.maxWidth = `${Math.max(220, rect.width)}px`;
      }
      if (existing.textContent !== text) existing.textContent = text;
      existing.disabled = !sourceExists;
      existing.dataset.sourceSessionId = relation.sourceSessionId;
      return;
    }
    const card = document.createElement('button');
    card.id = 'vibekits-continuation-source-card';
    card.type = 'button';
    card.className = 'vibekits-continuation-source-card';
    card.textContent = text;
    card.disabled = !sourceExists;
    card.dataset.sourceSessionId = relation.sourceSessionId;
    card.addEventListener('click', () => {
      const sourceId = card.dataset.sourceSessionId || '';
      if (!window.__vibekitsOpenSession(sourceId)) {
        window.__vibekitsOpenSessionByTitle(relation.sourceTitleSnapshot);
      }
    });
    if (host instanceof HTMLElement) {
      host.prepend(card);
    } else if (composer instanceof HTMLElement) {
      const rect = composer.getBoundingClientRect();
      card.classList.add('is-empty-session');
      card.style.left = `${Math.max(8, rect.left)}px`;
      card.style.top = `${Math.max(8, rect.top - 82)}px`;
      card.style.maxWidth = `${Math.max(220, rect.width)}px`;
      document.body.appendChild(card);
    }
  };

  const decorateContinuationTitles = () => {
    const selected = document.querySelector(
      '[role="treeitem"][aria-selected="true"]',
    );
    const currentId = window.__vibekitsCurrentSessionId() ||
      sessionIdForRow(selected) || activeSessionId;
    for (const relation of continuationRelations) {
      const title = String(relation.continuationTitleSnapshot || '').trim();
      if (!title) continue;
      const row = visibleSessionRows().find((candidate) =>
        sessionIdForRow(candidate) === relation.continuationSessionId,
      ) || (relation.continuationSessionId === currentId ? selected : null);
      if (!(row instanceof HTMLElement)) continue;
      row.dataset.vibekitsContinuationTitle = title;
      const label = [...row.querySelectorAll('*')].find((candidate) =>
        candidate instanceof HTMLElement &&
        candidate.children.length === 0 &&
        /^(?:新会话|New Session)$/i.test(candidate.textContent?.trim() || ''),
      );
      if (label instanceof HTMLElement) {
        label.textContent = title;
        label.title = title;
      }
    }
  };

  window.__vibekitsSetContinuationRelations = (relations, currentSessionId) => {
    continuationRelations = Array.isArray(relations) ? relations : [];
    activeSessionId = String(currentSessionId || '');
    if (pendingContinuation && continuationRelations.some((item) =>
      item.continuationSessionId ===
        pendingContinuation.continuationSessionId)) {
      pendingContinuation = null;
      sessionStorage.removeItem('vibekits.continuation.pending');
    }
    renderSyntheticContinuationRows();
    decorateContinuationTitles();
    renderContinuationCard();
  };

  window.__vibekitsSetPendingContinuation = (relation) => {
    pendingContinuation = relation && typeof relation === 'object'
      ? relation : null;
    if (pendingContinuation) {
      sessionStorage.setItem(
        'vibekits.continuation.pending', JSON.stringify(pendingContinuation),
      );
    } else {
      sessionStorage.removeItem('vibekits.continuation.pending');
    }
    renderSyntheticContinuationRows();
  };

  try {
    const savedProgress = JSON.parse(
      sessionStorage.getItem('vibekits.continuation.progress') || 'null',
    );
    if (savedProgress && Array.isArray(savedProgress.sessionIds)) {
      savedProgress.sessionTitles = Array.isArray(savedProgress.sessionTitles)
        ? savedProgress.sessionTitles : [];
      continuationProgress = savedProgress;
      requestAnimationFrame(window.__vibekitsRenderContinuationProgress);
    }
  } catch { sessionStorage.removeItem('vibekits.continuation.progress'); }

  try {
    const savedPending = JSON.parse(
      sessionStorage.getItem('vibekits.continuation.pending') || 'null',
    );
    if (savedPending?.continuationSessionId) {
      pendingContinuation = savedPending;
    }
  } catch { sessionStorage.removeItem('vibekits.continuation.pending'); }

  const visibleSessionRows = () =>
    [...document.querySelectorAll(
      '[role="treeitem"]:not([aria-expanded])',
    )].filter((row) => row instanceof HTMLElement &&
      row.offsetParent !== null && row.getClientRects().length > 0 &&
      row.getAttribute('aria-hidden') !== 'true');

  const renderSyntheticContinuationRows = () => {
    const relations = [...continuationRelations];
    if (pendingContinuation) relations.push(pendingContinuation);
    const wanted = new Set(relations.map((item) =>
      String(item.continuationSessionId || '')).filter(Boolean));
    for (const stale of document.querySelectorAll(
      '.vibekits-synthetic-continuation-row',
    )) {
      if (!wanted.has(stale.getAttribute('data-session-id') || '')) {
        stale.remove();
      }
    }
    const current = window.__vibekitsCurrentSessionId();
    for (const relation of relations) {
      const childId = String(relation.continuationSessionId || '');
      const childTitle = String(
        relation.continuationTitleSnapshot || '',
      ).trim();
      if (!childId || !childTitle) continue;
      const officialRow = visibleSessionRows().find((row) =>
        !row.classList.contains('vibekits-synthetic-continuation-row') &&
        (sessionIdForRow(row) === childId ||
          sessionTitleForRow(row) === childTitle),
      );
      const existing = document.querySelector(
        `.vibekits-synthetic-continuation-row[data-session-id="${CSS.escape(childId)}"]`,
      );
      if (officialRow) {
        existing?.remove();
        continue;
      }
      const sourceId = String(relation.sourceSessionId || '');
      const sourceTitle = String(relation.sourceTitleSnapshot || '').trim();
      const sourceRow = visibleSessionRows().find((row) =>
        !row.classList.contains('vibekits-synthetic-continuation-row') &&
        (sessionIdForRow(row) === sourceId ||
          sessionTitleForRow(row) === sourceTitle),
      );
      if (!(sourceRow instanceof HTMLElement)) continue;
      let row = existing;
      if (!(row instanceof HTMLElement)) {
        row = sourceRow.cloneNode(true);
        row.classList.add('vibekits-synthetic-continuation-row');
        row.setAttribute('data-session-id', childId);
        row.dataset.sourceSessionId = sourceId;
        row.dataset.sourceTitle = sourceTitle;
        sourceRow.parentElement?.insertBefore(row, sourceRow);
      }
      row.dataset.vibekitsContinuationTitle = childTitle;
      row.setAttribute('aria-selected', current === childId ? 'true' : 'false');
      const action = row.querySelector(
        'button[aria-label^="会话“"], button[aria-label^="Session "]',
      );
      if (action instanceof HTMLElement) {
        action.setAttribute('aria-label', `会话“${childTitle}”的操作`);
      }
      const label = [...row.querySelectorAll('*')].find((candidate) =>
        candidate instanceof HTMLElement && candidate.children.length === 0 &&
        candidate.textContent?.trim() === sourceTitle,
      );
      if (label instanceof HTMLElement) {
        label.textContent = childTitle;
        label.title = childTitle;
      }
      let state = row.querySelector('.vibekits-synthetic-session-state');
      const isPending = pendingContinuation?.continuationSessionId === childId;
      if (isPending && !(state instanceof HTMLElement)) {
        state = document.createElement('span');
        state.className = 'vibekits-synthetic-session-state';
        state.textContent = '整理中';
        row.appendChild(state);
      } else if (!isPending) {
        state?.remove();
      }
    }
  };

  if (!window.__vibekitsSyntheticContinuationRoutingInstalled) {
    window.__vibekitsSyntheticContinuationRoutingInstalled = true;
    document.addEventListener('click', (event) => {
      const target = event.target instanceof Element ? event.target : null;
      const row = target?.closest('.vibekits-synthetic-continuation-row');
      if (!(row instanceof HTMLElement) || target?.closest('button')) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      const sessionId = row.getAttribute('data-session-id') || '';
      if (/^session-[0-9a-f-]{36}$/.test(sessionId)) {
        openThroughOfficialWorkspace(sessionId);
      }
    }, true);
  }
  requestAnimationFrame(renderSyntheticContinuationRows);

  const focusVisibleComposer = () => {
    const composer = [...document.querySelectorAll(
      '[data-composer-card] textarea, [data-composer-card] [contenteditable="true"]',
    )].find((element) => element instanceof HTMLElement &&
      element.offsetParent !== null);
    composer?.focus();
  };

  window.__vibekitsFocusSessionAt = (position) => {
    const index = Number(position) - 1;
    const visibleSessions = visibleSessionRows();
    const target = visibleSessions[index];
    if (!(target instanceof HTMLElement)) {
      postHostMessage({
        type: 'vibekits.sessionShortcutMissing',
        position: index + 1,
      });
      return false;
    }
    const activationTarget = target.querySelector(
      'a[href], [role="link"], [data-session-id]',
    ) ?? target;
    activationTarget.focus({ preventScroll: true });
    activationTarget.click();
    postHostMessage({
      type: 'vibekits.sessionFocused',
      position: index + 1,
      sessionId: sessionIdForRow(target),
      title: sessionTitleForRow(target),
    });
    requestAnimationFrame(() => requestAnimationFrame(() => {
      target.scrollIntoView({ block: 'nearest' });
      focusVisibleComposer();
      window.setTimeout(focusVisibleComposer, 120);
    }));
    return true;
  };

  if (!window.__vibekitsSessionFunctionKeysInstalled) {
    window.__vibekitsSessionFunctionKeysInstalled = true;
    window.addEventListener('keydown', (event) => {
      if (event.isComposing || event.altKey || event.ctrlKey ||
          event.metaKey || event.shiftKey) return;
      const match = event.key.match(/^F([1-9]|1[0-2])$/);
      if (!match) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      window.__vibekitsFocusSessionAt(Number(match[1]));
    }, true);
  }

  const findConversationHost = () =>
    [...document.querySelectorAll('[data-conversation-scroll]')]
      .find((element) => element instanceof HTMLElement &&
        element.offsetParent !== null && element.clientHeight > 0);

  const scrollButtonId = 'vibekits-scroll-to-latest';
  let scrollButton = document.getElementById(scrollButtonId);
  if (!scrollButton) {
    scrollButton = document.createElement('button');
    scrollButton.id = scrollButtonId;
    scrollButton.type = 'button';
    scrollButton.textContent = '↓';
    scrollButton.title = '滚动到最新消息';
    scrollButton.setAttribute('aria-label', '滚动到最新消息');
    scrollButton.setAttribute('data-visible', 'false');
    scrollButton.addEventListener('click', () => {
      const host = findConversationHost();
      if (!(host instanceof HTMLElement)) return;
      host.scrollTo({ top: host.scrollHeight, behavior: 'smooth' });
    });
    document.body.appendChild(scrollButton);
  }

  const updateScrollToLatest = () => {
    const host = findConversationHost();
    const distance = host instanceof HTMLElement
      ? host.scrollHeight - host.clientHeight - host.scrollTop
      : 0;
    scrollButton?.setAttribute('data-visible', distance > 72 ? 'true' : 'false');
  };

  if (!window.__vibekitsScrollToLatestInstalled) {
    window.__vibekitsScrollToLatestInstalled = true;
    document.addEventListener('scroll', updateScrollToLatest, true);
    window.addEventListener('resize', updateScrollToLatest);
    const scrollObserver = new MutationObserver(() =>
      requestAnimationFrame(updateScrollToLatest));
    scrollObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
  }
  requestAnimationFrame(updateScrollToLatest);

  if (window.__vibekitsConversationWheelInstalled) return true;
  window.__vibekitsConversationWheelInstalled = true;

  window.addEventListener('wheel', (event) => {
    if (event.ctrlKey || event.deltaY === 0) return;
    const target = event.target instanceof Element
      ? event.target
      : event.target?.parentElement;
    const host = target?.closest?.('[data-conversation-scroll]') ||
      findConversationHost();
    if (!(host instanceof HTMLElement)) return;

    // Preserve native scrolling inside code, terminal and tool-result panes.
    // Once an inner pane reaches its edge, continue through the conversation.
    let node = target;
    while (node instanceof HTMLElement && node !== host) {
      const overflowY = getComputedStyle(node).overflowY;
      const scrollable = /auto|scroll/.test(overflowY) &&
        node.scrollHeight > node.clientHeight + 1;
      if (scrollable) {
        const canScroll = event.deltaY < 0
          ? node.scrollTop > 0
          : node.scrollTop + node.clientHeight < node.scrollHeight - 1;
        if (canScroll) return;
      }
      node = node.parentElement;
    }

    const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE
      ? 18
      : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
        ? host.clientHeight
        : 1;
    const before = host.scrollTop;
    host.scrollTop += event.deltaY * unit;
    if (host.scrollTop !== before) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, { capture: true, passive: false });

  return true;
})();
