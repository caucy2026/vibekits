(() => {
  const VERSION = 1;
  const COMPATIBILITY_PROFILE = 'dsh-fixed-conversation-v1';
  const hostPost = (payload) => {
    const message = JSON.stringify(payload);
    if (window.chrome?.webview?.postMessage) {
      window.chrome.webview.postMessage(message);
    } else if (window.VibekitsHost?.postMessage) {
      window.VibekitsHost.postMessage(message);
    }
  };

  const visible = (element) => {
    if (!(element instanceof HTMLElement)) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 20 && rect.height > 16 && style.display !== 'none' &&
      style.visibility !== 'hidden';
  };

  const composer = () => [...document.querySelectorAll(
    'textarea:not([disabled]):not([readonly]), [contenteditable="true"]',
  )].filter(visible).sort((left, right) =>
    left.getBoundingClientRect().bottom - right.getBoundingClientRect().bottom
  ).at(-1) || null;

  const label = (element) => [
    element?.getAttribute?.('aria-label'),
    element?.getAttribute?.('title'),
    element?.textContent,
  ].filter(Boolean).join(' ').trim();

  const buttonsNearComposer = () => {
    const input = composer();
    if (!input) return [];
    let scope = input.parentElement;
    for (let depth = 0; scope && depth < 5; depth += 1) {
      const buttons = [...scope.querySelectorAll('button')].filter(visible);
      if (buttons.length) return buttons;
      scope = scope.parentElement;
    }
    return [];
  };

  const stopButton = () => buttonsNearComposer().find((button) =>
    /stop|cancel|interrupt|停止|取消|打断/i.test(label(button))
  ) || null;

  const sendButton = () => buttonsNearComposer().find((button) =>
    /send|submit|发送|提交/i.test(label(button))
  ) || buttonsNearComposer().find((button) => button.type === 'submit') || null;

  const approvalWaiting = () => [...document.querySelectorAll(
    '[role="dialog"], [role="alertdialog"], [data-testid*="approval"]',
  )].filter(visible).some((element) =>
    /approve|approval|allow|permission|批准|审批|允许/i.test(label(element))
  );

  const identity = (prefix, element, fallback) => {
    const raw = [
      element?.getAttribute?.('data-id'),
      element?.getAttribute?.('data-key'),
      element?.getAttribute?.('aria-label'),
      element?.textContent,
      fallback,
    ].find((value) => String(value || '').trim()) || fallback;
    let hash = 2166136261;
    for (const character of `${prefix}:${raw}`) {
      hash ^= character.charCodeAt(0);
      hash = Math.imul(hash, 16777619);
    }
    return `${prefix}-${(hash >>> 0).toString(16)}`;
  };

  const context = () => {
    const selected = document.querySelector(
      '[role="treeitem"][aria-selected="true"]',
    );
    let workspace = selected?.parentElement;
    for (let depth = 0; workspace && depth < 6; depth += 1) {
      const candidate = workspace.querySelector?.(
        ':scope > [role="treeitem"][aria-expanded]',
      );
      if (candidate) {
        workspace = candidate;
        break;
      }
      workspace = workspace.parentElement;
    }
    return {
      workspaceId: identity('workspace', workspace, location.pathname),
      sessionId: identity('session', selected, location.pathname),
    };
  };

  const inputText = (element = composer()) => {
    if (element instanceof HTMLTextAreaElement) return element.value.trim();
    return element?.textContent?.trim() || '';
  };

  const setInput = (text) => {
    const element = composer();
    if (!element) return false;
    if (element instanceof HTMLTextAreaElement) {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype, 'value',
      )?.set;
      if (setter) setter.call(element, text);
      else element.value = text;
    } else {
      element.textContent = text;
    }
    element.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      inputType: text ? 'insertText' : 'deleteContentBackward',
      data: text,
    }));
    element.focus();
    return true;
  };

  const state = () => {
    const input = composer();
    const fixedProfileMatches = Boolean(
      document.querySelector('[data-conversation-scroll]') &&
      document.querySelector('[role="treeitem"]'),
    );
    return {
      compatible: Boolean(
        fixedProfileMatches && input && (sendButton() || stopButton()),
      ),
      compatibilityProfile: COMPATIBILITY_PROFILE,
      busy: Boolean(stopButton()),
      approvalWaiting: approvalWaiting(),
      ...context(),
    };
  };

  const failureText = () => [...document.querySelectorAll(
    '[role="alert"], [role="status"]',
  )].filter(visible).map(label).find((text) =>
    /failed|failure|error|失败|错误/i.test(text)
  ) || '';

  let previousState = null;
  let pendingIdempotencyKey = '';
  let cancellationRequested = false;
  const publishState = () => {
    const current = state();
    const signature = JSON.stringify(current);
    if (signature === window.__vibekitsHarnessQueueStateSignature) return;
    window.__vibekitsHarnessQueueStateSignature = signature;
    hostPost({type: 'vibekits.harnessEvent', event: 'state', ...current});
    if (previousState && !previousState.busy && current.busy) {
      hostPost({type: 'vibekits.harnessEvent', event: 'turn.started', ...current});
    }
    if (previousState?.busy && !current.busy) {
      const failed = failureText();
      hostPost({
        type: 'vibekits.harnessEvent',
        event: cancellationRequested
          ? 'turn.cancelled'
          : failed ? 'turn.failed' : 'turn.completed',
        message: failed,
        ...current,
      });
      cancellationRequested = false;
    }
    if (!previousState?.approvalWaiting && current.approvalWaiting) {
      hostPost({
        type: 'vibekits.harnessEvent',
        event: 'approval.waiting',
        ...current,
      });
    }
    previousState = current;
  };

  const ensureQueueControl = () => {
    const input = composer();
    if (!input || !state().compatible) return;
    let control = document.getElementById('vibekits-harness-queue-control');
    if (!control) {
      control = document.createElement('button');
      control.id = 'vibekits-harness-queue-control';
      control.type = 'button';
      control.textContent = '待执行 0';
      control.title = '查看、编辑或调整待执行消息';
      control.setAttribute('aria-label', '待执行消息');
      control.addEventListener('click', () => hostPost({
        type: 'vibekits.queue.open',
        ...context(),
      }));
      document.body.appendChild(control);
    }
    const rect = input.getBoundingClientRect();
    control.style.left = `${Math.max(12, rect.right - control.offsetWidth)}px`;
    control.style.top = `${Math.max(8, rect.top - 32)}px`;
  };

  if (!document.getElementById('vibekits-harness-queue-style')) {
    const style = document.createElement('style');
    style.id = 'vibekits-harness-queue-style';
    style.textContent = `
      #vibekits-harness-queue-control {
        position: fixed; z-index: 2147482990; min-width: 78px; height: 26px;
        padding: 0 10px; border: 1px solid rgba(120,120,120,.24);
        border-radius: 13px; background: color-mix(in srgb, Canvas 94%, transparent);
        color: CanvasText; font: 12px/24px system-ui,sans-serif; cursor: pointer;
        box-shadow: 0 2px 8px rgba(0,0,0,.08);
      }
      #vibekits-harness-queue-control:hover { filter: brightness(.97); }
      #vibekits-harness-queue-control:focus-visible {
        outline: 2px solid #6f8cff; outline-offset: 2px;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  window.__vibekitsHarnessQueueBridge = {
    version: VERSION,
    probe: state,
    setQueueCount(count) {
      ensureQueueControl();
      const control = document.getElementById('vibekits-harness-queue-control');
      if (control) control.textContent = `待执行 ${Math.max(0, Number(count) || 0)}`;
    },
    composerText() { return inputText(); },
    clearComposer() { return setInput(''); },
    submit(text, idempotencyKey) {
      if (!state().compatible || state().busy || state().approvalWaiting) {
        return false;
      }
      if (!setInput(String(text || ''))) return false;
      const button = sendButton();
      if (!button || button.disabled) return false;
      pendingIdempotencyKey = String(idempotencyKey || '');
      button.click();
      let acceptanceChecks = 0;
      const confirmAccepted = () => {
        const accepted = inputText() === '' || state().busy;
        if (accepted) {
          hostPost({
            type: 'vibekits.harnessEvent',
            event: 'message.accepted',
            idempotencyKey: pendingIdempotencyKey,
            ...state(),
          });
          pendingIdempotencyKey = '';
        } else if (++acceptanceChecks < 30) {
          window.setTimeout(confirmAccepted, 100);
        }
      };
      window.setTimeout(confirmAccepted, 100);
      return true;
    },
    cancel() {
      const button = stopButton();
      if (!button) return false;
      cancellationRequested = true;
      button.click();
      return true;
    },
  };

  if (!window.__vibekitsHarnessQueueObserverInstalled) {
    window.__vibekitsHarnessQueueObserverInstalled = true;
    let timer = 0;
    const schedule = () => {
      clearTimeout(timer);
      timer = window.setTimeout(() => {
        ensureQueueControl();
        publishState();
      }, 80);
    };
    new MutationObserver(schedule).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['aria-label', 'aria-selected', 'disabled'],
      childList: true,
      subtree: true,
    });
    window.addEventListener('resize', schedule);
    document.addEventListener('click', (event) => {
      const button = event.target instanceof Element
        ? event.target.closest('button')
        : null;
      if (!button || button.id === 'vibekits-harness-queue-control') return;
      if (state().busy && /send|submit|发送|提交/i.test(label(button))) {
        hostPost({type: 'vibekits.queue.steered', ...context()});
      }
    }, true);
  }
  ensureQueueControl();
  publishState();
  return true;
})();
