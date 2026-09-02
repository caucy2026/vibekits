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

  const styleId = 'vibekits-codex-conversation-ux';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      [data-conversation-scroll] {
        overscroll-behavior: contain;
        touch-action: pan-y;
      }

      /* Match Codex's compact reading density without shrinking navigation. */
      [data-conversation-scroll] .Sxvs8a_root,
      [data-conversation-scroll] .gdEzaW_bubble {
        font-size: 12px !important;
        line-height: 18px !important;
      }

      [data-conversation-scroll] .uV2eYG_card {
        font-size: 14px !important;
        line-height: 21px !important;
      }

      [data-conversation-scroll] [data-chat-flow] [data-chat-anchor-key],
      [data-conversation-scroll] [data-chat-flow] p,
      [data-conversation-scroll] [data-chat-flow] li,
      [data-conversation-scroll] [data-chat-flow] blockquote {
        font-size: 12px !important;
        line-height: 18px !important;
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

      [data-conversation-scroll] .CY-8Ka_title,
      [data-conversation-scroll] .CY-8Ka_summary,
      [data-conversation-scroll] .pC0e7a_source,
      [data-conversation-scroll] .pC0e7a_summary,
      [data-conversation-scroll] ._Xvjua_summary,
      [data-conversation-scroll] .gdEzaW_compactionTitle,
      [data-conversation-scroll] .gdEzaW_compactionSummary,
      [data-conversation-scroll] .gdEzaW_compactionBody {
        font-size: 12px !important;
        line-height: 18px !important;
      }

      [data-conversation-scroll] .Sxvs8a_root pre,
      [data-conversation-scroll] .Sxvs8a_root code {
        font-size: 12px !important;
        line-height: 18px !important;
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
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }
  markSelectedSessionActions();

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
