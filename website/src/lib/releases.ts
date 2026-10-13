export const REPOSITORY = 'https://github.com/notnotshuts/Mafus';
export const RELEASES = `${REPOSITORY}/releases`;
export const RELEASE_API = 'https://api.github.com/repos/notnotshuts/Mafus/releases/latest';
export type Architecture = 'arm64' | 'x86_64';
export type ReleaseAsset = { name:string; size:number; browser_download_url:string; digest?:string };
export type Release = { tag_name:string; html_url:string; draft:boolean; prerelease:boolean; assets:ReleaseAsset[] };
export function validRelease(value:unknown):value is Release {
  if(!value || typeof value !== 'object')return false;
  const release=value as Partial<Release>;
  return typeof release.tag_name==='string' && /^v\d+\.\d+\.\d+$/.test(release.tag_name)
    && release.html_url===`${RELEASES}/tag/${release.tag_name}` && release.draft===false
    && release.prerelease===false && Array.isArray(release.assets)
    && release.assets.every(asset=>asset && typeof asset.name==='string' && typeof asset.size==='number' && typeof asset.browser_download_url==='string');
}
export function releaseAsset(release:Release,architecture:Architecture):ReleaseAsset|undefined {
  const name=`Mafus-${release.tag_name.slice(1)}-macOS-${architecture}.zip`;
  return release.assets.find(asset=>asset.name===name && asset.size>0
    && asset.browser_download_url===`${RELEASES}/download/${release.tag_name}/${name}`);
}
export function assetPath(path:string){return `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/${path}`;}
