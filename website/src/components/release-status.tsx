'use client';
import {ArrowUpRight,RefreshCw} from 'lucide-react';
import {useRelease} from './release-provider';
import {RELEASES} from '@/lib/releases';
export function ReleaseStatus(){const {release,loading,stale,error,refresh}=useRelease();return <div className="release-status" aria-live="polite"><a href={release?.html_url??RELEASES} target="_blank" rel="noopener noreferrer">{release?release.tag_name:loading?'Проверяем релиз…':'Все релизы'}<ArrowUpRight className="size-3"/></a><span aria-hidden="true">·</span><span>macOS 14+</span>{(stale||error)&&<button type="button" onClick={refresh} disabled={loading} className="release-refresh" aria-label="Обновить информацию о релизе"><RefreshCw className={`size-3 ${loading?'animate-spin':''}`}/><span>{stale?'Сохранённая версия':'Повторить'}</span></button>}</div>;}
