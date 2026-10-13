import {ArrowUpRight} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {REPOSITORY} from '@/lib/releases';
import {ThemeToggle} from './theme-toggle';
import {DownloadDialog} from './download-dialog';
export function Header(){return <header className="site-header"><div className="site-width header-inner"><a href="#top" className="wordmark" aria-label="Mafus — на главную">mafus<span>.</span></a><nav aria-label="Основная навигация"><a href="#possibilities" className="nav-link">Возможности</a><a href={REPOSITORY} target="_blank" rel="noopener noreferrer" className="nav-link github-nav">GitHub<ArrowUpRight className="size-3.5"/></a><ThemeToggle/><DownloadDialog><Button size="sm" className="nav-download">Скачать</Button></DownloadDialog></nav></div></header>;}
