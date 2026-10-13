'use strict';
const REPO = 'https://github.com/notnotshuts/Mafus';
const RELEASES = REPO + '/releases';
const CACHE_KEY = 'mafus-latest-release-v2';
const TTL = 15 * 60 * 1000;

function validRelease(release) {
  if (!release || release.draft || release.prerelease || typeof release.tag_name !== 'string' || !Array.isArray(release.assets)) return false;
  return release.html_url === RELEASES + '/tag/' + encodeURIComponent(release.tag_name);
}
function releaseAsset(release, architecture) {
  const pattern = new RegExp('^Mafus-[0-9]+\\.[0-9]+\\.[0-9]+-macOS-' + architecture + '\\.zip$');
  return release.assets.find(asset => pattern.test(asset.name) && asset.browser_download_url === RELEASES + '/download/' + encodeURIComponent(release.tag_name) + '/' + asset.name && asset.size > 0);
}
function showRelease(release, cached = false) {
  if (!validRelease(release)) return false;
  for (const arch of ['arm64', 'x86_64']) {
    const asset = releaseAsset(release, arch);
    const link = document.getElementById('download-' + arch);
    link.href = asset ? asset.browser_download_url : release.html_url;
    link.title = asset ? Math.round(asset.size / 1048576) + ' МБ · ZIP' : 'Открыть доступные сборки релиза';
    link.dataset.available = String(Boolean(asset));
  }
  const intel = releaseAsset(release, 'x86_64');
  document.getElementById('release-status').textContent = release.tag_name + ' · ' + (intel ? 'Apple Silicon и Intel' : 'Apple Silicon · Intel: смотрите доступные сборки') + (cached ? ' · сохранённые данные' : '');
  const link = document.getElementById('release-link');
  link.href = release.html_url; link.textContent = release.tag_name + ' ↗';
  return true;
}
async function loadRelease() {
  let cached;
  try { cached = JSON.parse(localStorage.getItem(CACHE_KEY)); } catch {}
  const hasCache = cached && showRelease(cached.release, true);
  if (hasCache && Number.isFinite(cached.timestamp) && Date.now() >= cached.timestamp && Date.now() - cached.timestamp < TTL) return;
  try {
    const response = await fetch('https://api.github.com/repos/notnotshuts/Mafus/releases/latest', {headers: {Accept:'application/vnd.github+json'}, signal: AbortSignal.timeout(8000)});
    if (!response.ok) throw new Error('Release unavailable');
    const release = await response.json();
    if (!showRelease(release)) throw new Error('Invalid release');
    try { localStorage.setItem(CACHE_KEY, JSON.stringify({timestamp:Date.now(),release})); } catch {}
  } catch {
    if (!hasCache) document.getElementById('release-status').textContent = 'Последние версии доступны на GitHub ↗';
  }
}
if (typeof document !== 'undefined') {
  const themeButton = document.getElementById('theme');
  function updateThemeButton() {
    const dark = document.documentElement.dataset.theme === 'dark';
    themeButton.textContent = dark ? '☀' : '☾';
    themeButton.setAttribute('aria-label', dark ? 'Включить светлую тему' : 'Включить тёмную тему');
    document.querySelector('meta[name="theme-color"]').content = dark ? '#111115' : '#f6f5fa';
  }
  themeButton.addEventListener('click', () => {
    const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = theme;
    try {localStorage.setItem('mafus-theme', theme)} catch {}
    updateThemeButton();
  });
  updateThemeButton();
  const systems = {
    windows:{file:'Windows11_x64.iso',format:'NTFS · UEFI:NTFS',mode:'Установочный USB для UEFI'},
    linux:{file:'linuxmint-cinnamon.iso',format:'Live ISO · ext4 persistence',mode:'Linux Live · сохранять изменения'},
    dos:{file:'FD14-LiteUSB.zip',format:'FreeDOS · загрузочный IMG',mode:'DOS · BIOS / CSM'}
  };
  const tabs = [...document.querySelectorAll('[data-system]')];
  function selectTab(tab) {
    for (const button of tabs) {button.setAttribute('aria-selected', String(button === tab));button.tabIndex = button === tab ? 0 : -1;}
    const item = systems[tab.dataset.system];
    for (const field of ['file','format','mode']) document.getElementById('demo-' + field).textContent = item[field];
    document.getElementById('demo-panel').setAttribute('aria-labelledby', tab.id);
  }
  tabs.forEach((tab, index) => {
    tab.id = 'system-' + tab.dataset.system;tab.setAttribute('aria-controls','demo-panel');
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {
      const keys = {ArrowRight:(index+1)%tabs.length,ArrowLeft:(index+tabs.length-1)%tabs.length,Home:0,End:tabs.length-1};
      if (event.key in keys) {event.preventDefault();const target=tabs[keys[event.key]];selectTab(target);target.focus();}
    });
  });
  selectTab(tabs[0]);
  loadRelease();
}
if (typeof module !== 'undefined') module.exports = {validRelease,releaseAsset};
