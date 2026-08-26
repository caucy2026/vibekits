(() => {
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
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  localizeOfficialActions();
  if (!window.__vibekitsConversationLocalizationInstalled) {
    window.__vibekitsConversationLocalizationInstalled = true;
    const observer = new MutationObserver(localizeOfficialActions);
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  if (window.__vibekitsConversationWheelInstalled) return true;
  window.__vibekitsConversationWheelInstalled = true;

  window.addEventListener('wheel', (event) => {
    if (event.ctrlKey || event.deltaY === 0) return;
    const target = event.target instanceof Element
      ? event.target
      : event.target?.parentElement;
    const host = target?.closest?.('[data-conversation-scroll]') ||
      [...document.querySelectorAll('[data-conversation-scroll]')]
        .find((element) => element instanceof HTMLElement &&
          element.offsetParent !== null && element.clientHeight > 0);
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
