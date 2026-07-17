// Morii solid icon registry — one source. <Icon name> renders it. Shell adds viewBox + live-area frame.
export const icons: Record<string, string> = {
  dashboard: '<rect x="3" y="3" width="8" height="8" rx="2.4"/><rect x="13" y="3" width="8" height="5.4" rx="2.2"/><rect x="13" y="10.6" width="8" height="10.4" rx="2.4"/><rect x="3" y="13" width="8" height="8" rx="2.4"/>',
  nodes: '<path fill-rule="evenodd" d="M4.5 3.5h15A2.5 2.5 0 0 1 22 6v3.2A2.5 2.5 0 0 1 19.5 11.7h-15A2.5 2.5 0 0 1 2 9.2V6A2.5 2.5 0 0 1 4.5 3.5Zm2 3.55a1.05 1.05 0 1 0 0 2.1 1.05 1.05 0 0 0 0-2.1Z"/><path fill-rule="evenodd" d="M4.5 12.8h15A2.5 2.5 0 0 1 22 15.3v3.2A2.5 2.5 0 0 1 19.5 21h-15A2.5 2.5 0 0 1 2 18.5v-3.2A2.5 2.5 0 0 1 4.5 12.8Zm2 3.55a1.05 1.05 0 1 0 0 2.1 1.05 1.05 0 0 0 0-2.1Z"/>',
  members: '<path opacity=".42" d="M16.4 4.4a3.2 3.2 0 1 0 0 6.4 3.2 3.2 0 0 0 0-6.4Zm-.2 7.8c-.9 0-1.7.15-2.5.45 1.9 1.25 3.05 3.15 3.2 5.35H22v-.6c0-2.85-2.6-5.15-5.8-5.15Z"/><path d="M9 3.4a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6Z"/><path d="M9 12.1c-3.95 0-7 2.5-7 5.6V19a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-1.3c0-3.1-3.05-5.6-7-5.6Z"/>',
  sub: '<path d="M7.4 8.9 13.8 5.7M7.4 15.1 13.8 18.3" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><circle cx="5" cy="12" r="3.4"/><circle cx="17.6" cy="5.5" r="3.2"/><circle cx="17.6" cy="18.5" r="3.2"/>',
  traffic: '<rect x="3" y="12.5" width="4.4" height="8.5" rx="1.6"/><rect x="9.8" y="7.4" width="4.4" height="13.6" rx="1.6"/><rect x="16.6" y="3" width="4.4" height="18" rx="1.6"/>',
  settings: '<rect x="2.6" y="6.3" width="18.8" height="3" rx="1.5"/><rect x="2.6" y="14.7" width="18.8" height="3" rx="1.5"/><path fill-rule="evenodd" d="M8 4.5a3.3 3.3 0 1 0 0 6.6 3.3 3.3 0 0 0 0-6.6Zm0 2.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3Z"/><path fill-rule="evenodd" d="M15.6 12.9a3.3 3.3 0 1 0 0 6.6 3.3 3.3 0 0 0 0-6.6Zm0 2.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3Z"/>',
  add: '<rect x="10.2" y="4" width="3.6" height="16" rx="1.8"/><rect x="4" y="10.2" width="16" height="3.6" rx="1.8"/>',
  close: '<path d="M6.4 6.4 17.6 17.6M17.6 6.4 6.4 17.6" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>',
  chevron: '<path d="M9 5.4 15.6 12 9 18.6" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
  edit: '<path d="M3.9 16.5 14.5 5.9l3.6 3.6L7.5 20.1H3.9Z"/><path d="M16 4.4l1.3-1.3a2 2 0 0 1 2.85 0l.75.75a2 2 0 0 1 0 2.85L19.6 8Z" opacity=".5"/>',
  theme: '<circle cx="12" cy="12" r="4.6"/><path d="M12 2.2v2.6M12 19.2v2.6M2.2 12h2.6M19.2 12h2.6M5 5l1.85 1.85M17.15 17.15 19 19M19 5l-1.85 1.85M6.85 17.15 5 19" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/>',
  logout: '<path d="M12.5 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h6.5a1 1 0 1 0 0-2H6V5h6.5a1 1 0 1 0 0-2Z"/><path d="M15.7 7.8a1 1 0 0 0-1.4 1.4L16.1 11H10a1 1 0 1 0 0 2h6.1l-1.8 1.8a1 1 0 0 0 1.4 1.4l3.5-3.5a1 1 0 0 0 0-1.4Z"/>',
  shield: '<path fill-rule="evenodd" d="M12 2 4 5v6.2c0 5 3.4 8.6 8 10 4.6-1.4 8-5 8-10V5Zm3.55 6.85a1 1 0 0 0-1.6-1.2l-3.05 3.95-1.35-1.35a1 1 0 0 0-1.4 1.4l2.15 2.15a1 1 0 0 0 1.5-.1Z"/>',
  bolt: '<path d="M13.6 2.3 5.3 12.5a1 1 0 0 0 .8 1.6h4.1l-1.4 7a.6.6 0 0 0 1.1.45l8.1-10.35a1 1 0 0 0-.8-1.6h-4l1.5-6.4a.6.6 0 0 0-1.1-.4Z"/>',
  copy: '<path fill-rule="evenodd" d="M9.2 2h7.8A2.6 2.6 0 0 1 19.6 4.6v10A2.6 2.6 0 0 1 17 17.2h-.6V8.2A3.6 3.6 0 0 0 12.8 4.6H6.7A2.6 2.6 0 0 1 9.2 2Z"/><rect x="4" y="6.2" width="11.6" height="15.8" rx="2.6"/>',
  calendar: '<path d="M6 4.2h12a3 3 0 0 1 3 3v1H3v-1a3 3 0 0 1 3-3Z" opacity=".4"/><path d="M8 2.2a1 1 0 0 0-1 1v1.9h2V3.2a1 1 0 0 0-1-1Zm8 0a1 1 0 0 0-1 1v1.9h2V3.2a1 1 0 0 0-1-1Z"/><path fill-rule="evenodd" d="M3 9.2h18v8.6A3.2 3.2 0 0 1 17.8 21H6.2A3.2 3.2 0 0 1 3 17.8Zm5 3a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Zm4 0a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Zm4 0a1.1 1.1 0 1 0 0 2.2 1.1 1.1 0 0 0 0-2.2Z"/>',
  probe: '<path d="M2.5 12h4l2.4-6.4a.7.7 0 0 1 1.3.05L12.7 18l2.1-6a.7.7 0 0 1 .66-.47H21.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>',
}
export type IconName = keyof typeof icons
