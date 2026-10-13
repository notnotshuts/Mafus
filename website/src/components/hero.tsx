import {ArrowDown,ArrowUpRight} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {REPOSITORY} from '@/lib/releases';
import {DownloadDialog} from './download-dialog';
import {ReleaseStatus} from './release-status';
import {AppPreview} from './app-preview';
export function Hero(){return <section className="hero-section" aria-labelledby="hero-title"><div className="site-width"><p className="eyebrow">MAFUS ДЛЯ MAC</p><h1 id="hero-title">Загрузочный USB.<br/><span>Всё просто.</span></h1><p className="hero-description">Windows, Linux и FreeDOS.<br className="mobile-break"/> Новая система начинается<br className="desktop-break"/> с вашей флешки и вашего Mac.</p><div className="hero-actions"><DownloadDialog><Button className="primary-cta">Скачать для Mac<ArrowDown className="size-4"/></Button></DownloadDialog><Button asChild variant="ghost" className="secondary-cta"><a href={REPOSITORY} target="_blank" rel="noopener noreferrer">Открытый код<ArrowUpRight className="size-4"/></a></Button></div><ReleaseStatus/><AppPreview/></div></section>;}
