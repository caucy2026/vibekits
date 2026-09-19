(() => {
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
        border: 1px solid rgba(120, 120, 120, 0.22);
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.96);
        color: rgba(45, 45, 45, 0.76);
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
        outline: 2px solid #6f8cff;
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

  const visibleSessionRows = () =>
    [...document.querySelectorAll(
      '[role="treeitem"]:not([aria-expanded])',
    )].filter((row) => row instanceof HTMLElement &&
      row.offsetParent !== null && row.getClientRects().length > 0 &&
      row.getAttribute('aria-hidden') !== 'true');

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
    target.click();
    requestAnimationFrame(() => requestAnimationFrame(focusVisibleComposer));
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
