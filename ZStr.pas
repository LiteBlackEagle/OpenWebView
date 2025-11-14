// ==============================================================================
// FILE: ZStr.pas (PHIÊN BẢN CUỐI CÙNG - STABLE)
// ==============================================================================
unit ZStr;

interface

uses
  System.SysUtils, System.Classes, Winapi.WebView2, edge, System.NetEncoding;

procedure zNotifier(br: TCustomEdgeBrowser; noti: string; ColorID: Integer = 0);

implementation

procedure zNotifier(br: TCustomEdgeBrowser; noti: string; ColorID: Integer = 0);
var
  script: string;
  sColorID: string;
begin
  noti := StringReplace(noti, '`', '\`', [rfReplaceAll]);
  noti := StringReplace(noti, '\', '\\', [rfReplaceAll]);
  noti := StringReplace(noti, '${', '$\{', [rfReplaceAll]);
  sColorID := IntToStr(ColorID);

  script :=
'''
(function() {
    // ======================================================================
    // LOGIC KHỞI TẠO DUY NHẤT - Chỉ chạy MỘT LẦN cho mỗi trang
    // ======================================================================
    if (typeof window.Z_ProcessNotifierQueue === 'undefined') {

        // Cờ để đảm bảo logic setup UI chỉ chạy một lần
        let isUISetup = false;

        // Bảng màu
        const COLOR_PALETTE = [
            '#00aeff', '#34d399', '#a78bfa', '#f97316', '#ef4444',
            '#ec4899', '#eab308', '#14b8a6', '#6366f1', '#8b5cf6', '#d946ef'
        ];

        // Hàm tạo một thông báo trên UI
        const runNotifier = (notification) => {
            const notificationText = notification.text;
            const colorId = parseInt(notification.colorId, 10) || 0;
            const accentColor = COLOR_PALETTE[colorId] || COLOR_PALETTE[0];

            let container = document.getElementById('z-notifier-container');

            // Nếu container chưa tồn tại, tạo nó (chỉ xảy ra một lần)
            if (!container) {
                const style = document.createElement('style');
                style.textContent = `
                    #z-notifier-container { position: fixed; top: 10px; right: 10px; z-index: 2147483646; display: flex; flex-direction: column; gap: 8px; pointer-events: none; }
                    .z-notification { width: 240px; background: rgba(20, 20, 20, 0.85); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 8px; color: #f0f0f0; border-left: 3px solid var(--accent-color); display: flex; align-items: flex-start; padding: 10px 14px; gap: 12px; opacity: 0; transform: translateY(-20px) scale(0.95); transition: all 0.4s cubic-bezier(0.2, 0.8, 0.2, 1); pointer-events: auto; cursor: pointer; position: relative; overflow: hidden; }
                    .z-notification.dimmed { opacity: 0.6; background: rgba(30, 30, 30, 0.3); border-color: rgba(255, 255, 255, 0.05); border-left-color: #555; backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px); transform: scale(0.98); }
                    .z-notification:hover { opacity: 1; background: rgba(35, 35, 35, 0.9); border-color: var(--accent-color); transform: scale(1); }
                    .z-notification.visible { transform: translateY(0) scale(1); opacity: 1; }
                    .z-notification.closing { transform: translateX(110%); opacity: 0; }
                    .z-notification-icon { width: 18px; height: 18px; flex-shrink: 0; color: var(--accent-color); margin-top: 1px; transition: color 0.3s ease; }
                    .z-notification-content { display: flex; flex-direction: column; gap: 2px; flex-grow: 1; overflow: hidden; }
                    .z-notification-title { font-weight: 240; font-size: 14px; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; text-overflow: ellipsis; white-space: pre-wrap; word-break: break-word; }
                    .z-notification-time { font-size: 11px; color: #999; font-family: monospace; }
                    .z-notification-copy-btn { width: 24px; height: 24px; flex-shrink: 0; display: flex; align-items: center; justify-content: center; border-radius: 50%; color: #888; cursor: pointer; transition: background-color 0.2s, color 0.2s; }
                    .z-notification-copy-btn:hover { background-color: rgba(255, 255, 255, 0.1); color: #fff; }
                    .z-notification::before { content: ''; position: absolute; top: 0; left: -100%; width: 100%; height: 2px; background: linear-gradient(90deg, transparent, var(--accent-color), transparent); animation: z-notifier-glow 1.2s linear; }
                    @keyframes z-notifier-glow { 0% { left: -100%; } 100% { left: 100%; } }
                `;
                document.head.appendChild(style);
                container = document.createElement('div');
                container.id = 'z-notifier-container';
                document.body.appendChild(container);
            }

            container.querySelectorAll('.z-notification:not(.dimmed)').forEach(el => el.classList.add('dimmed'));
            while (container.childNodes.length >= 5) { container.lastChild?.remove(); }

            const notificationElement = document.createElement('div');
            notificationElement.className = 'z-notification';
            notificationElement.style.setProperty('--accent-color', accentColor);

            const now = new Date();
            const timeString = now.getHours().toString().padStart(2, '0') + ':' + now.getMinutes().toString().padStart(2, '0') + ':' + now.getSeconds().toString().padStart(2, '0');

            let zNotifierPolicy; try { zNotifierPolicy = window.trustedTypes.createPolicy('z-notifier-policy-' + Date.now(), { createHTML: string => string }); } catch (e) {}
            const setSafeHTML = (element, html) => { if (zNotifierPolicy) element.innerHTML = zNotifierPolicy.createHTML(html); else element.innerHTML = html; };
            setSafeHTML(notificationElement, `<div class="z-notification-icon"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg></div><div class="z-notification-content"><div class="z-notification-title">${notificationText}</div><div class="z-notification-time">${timeString}</div></div><div class="z-notification-copy-btn" title="Copy"><svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg></div>`);

            let autoCloseTimer = null;
            const closeNotification = () => { notificationElement.classList.add('closing'); setTimeout(() => notificationElement.remove(), 400); };
            const startAutoCloseTimer = () => { clearTimeout(autoCloseTimer); autoCloseTimer = setTimeout(closeNotification, 3000); };
            notificationElement.onclick = (e) => { if (!e.target.closest('.z-notification-copy-btn')) { closeNotification(); } };
            const copyBtn = notificationElement.querySelector('.z-notification-copy-btn');
            if (copyBtn) { copyBtn.onclick = (e) => { e.stopPropagation(); navigator.clipboard.writeText(notificationText).then(() => { copyBtn.style.color = '#28a745'; setTimeout(() => { copyBtn.style.color = '#888'; }, 800); }); }; }
            notificationElement.onmouseenter = () => clearTimeout(autoCloseTimer);
            notificationElement.onmouseleave = startAutoCloseTimer;

            container.prepend(notificationElement);
            requestAnimationFrame(() => notificationElement.classList.add('visible'));
            startAutoCloseTimer();
        };

        // HÀM XỬ LÝ TRUNG TÂM
        window.Z_ProcessNotifierQueue = function() {
            // Nếu UI chưa được thiết lập, hãy thiết lập nó
            if (!isUISetup) {
                // Kiểm tra xem trang đã load xong chưa
                if (document.readyState === 'complete' && document.body) {
                    isUISetup = true;
                } else {
                    // Nếu chưa, đợi sự kiện `load` và thoát.
                    // Sự kiện `load` sẽ gọi lại hàm này.
                    return;
                }
            }

            // Nếu đã đến đây, UI đã sẵn sàng
            const queue = window.zNotifierQueue || [];
            if (queue.length === 0) return;

            queue.forEach(notification => runNotifier(notification));
            window.zNotifierQueue = []; // Xóa hàng đợi
        };

        // Đăng ký bộ lắng nghe sự kiện `load` một lần duy nhất
        if (document.readyState === 'complete') {
            window.Z_ProcessNotifierQueue();
        } else {
            window.addEventListener('load', window.Z_ProcessNotifierQueue, { once: true });
        }
    }

    // ======================================================================
    // LOGIC CHẠY MỖI LẦN - Luôn luôn an toàn
    // ======================================================================
    if (typeof window.zNotifierQueue === 'undefined') {
        window.zNotifierQueue = [];
    }
    window.zNotifierQueue.push({ text: `
'''
+
noti
+
'''
`, colorId:
'''
+
sColorID
+
'''
});

    // Kích hoạt hàm xử lý trung tâm
    if (window.Z_ProcessNotifierQueue) {
        window.Z_ProcessNotifierQueue();
    }
})();
'''
;
  br.ExecuteScript(script);
end;

end.
