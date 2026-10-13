'use client';
import {useState,type ReactNode} from 'react';
import {ArrowDown,ArrowUpRight,Check,Copy,Cpu,ExternalLink,LoaderCircle,RefreshCw} from 'lucide-react';
import {toast} from 'sonner';
import {Button} from '@/components/ui/button';
import {Badge} from '@/components/ui/badge';
import {Dialog,DialogContent,DialogDescription,DialogHeader,DialogTitle,DialogTrigger} from '@/components/ui/dialog';
import {RadioGroup,RadioGroupItem} from '@/components/ui/radio-group';
import {Accordion,AccordionContent,AccordionItem,AccordionTrigger} from '@/components/ui/accordion';
import {Skeleton} from '@/components/ui/skeleton';
import {RELEASES,releaseAsset,type Architecture} from '@/lib/releases';
import {useRelease} from './release-provider';
export function DownloadDialog({children}:{children:ReactNode}){
  const [architecture,setArchitecture]=useState<Architecture>('arm64');
  const [copied,setCopied]=useState(false);
  const {release,loading,stale,error,refresh}=useRelease();
  const asset=release?releaseAsset(release,architecture):undefined;
  const checksum=asset?.digest?.match(/^sha256:([a-f0-9]{64})$/)?.[1];
  async function copyChecksum(){
    if(!checksum)return;
    try{await navigator.clipboard.writeText(checksum);setCopied(true);toast.success('SHA-256 скопирована');setTimeout(()=>setCopied(false),2000);}catch{toast.error('Не удалось скопировать. Суммы доступны в релизе GitHub.');}
  }
  return <Dialog><DialogTrigger asChild>{children}</DialogTrigger><DialogContent className="download-dialog sm:max-w-[520px]" aria-describedby="download-description">
    <DialogHeader><div className="dialog-icon"><ArrowDown strokeWidth={1.7}/></div><DialogTitle>Mafus для вашего Mac.</DialogTitle><DialogDescription id="download-description">Выберите процессор вашего Mac. Все инструменты уже входят в приложение.</DialogDescription></DialogHeader>
    <div className="dialog-release">{loading&&!release?<Skeleton className="h-5 w-28"/>:<Badge variant="secondary">{release?.tag_name??'GitHub Releases'}</Badge>}<span>macOS 14 и новее</span></div>
    <RadioGroup value={architecture} onValueChange={value=>{setArchitecture(value as Architecture);setCopied(false);}} aria-label="Процессор Mac" className="architecture-options">
      {[{value:'arm64',title:'Apple Silicon',detail:'Mac с чипом серии M',label:'M'},{value:'x86_64',title:'Intel',detail:'Mac с процессором Intel',label:'intel'}].map(item=><label key={item.value} className="architecture-option" data-selected={architecture===item.value}><span className={`chip-mark ${item.value==='x86_64'?'chip-intel':''}`}>{item.label}</span><span className="architecture-text"><strong>{item.title}</strong><small>{item.detail}</small></span><RadioGroupItem value={item.value} aria-label={item.title}/></label>)}
    </RadioGroup>
    <Accordion type="single" collapsible className="architecture-help"><AccordionItem value="processor"><AccordionTrigger>Как узнать процессор своего Mac?</AccordionTrigger><AccordionContent>Откройте меню Apple  → «Об этом Mac». Если указано «Чип Apple M…», выбирайте Apple Silicon. Если указан процессор Intel — выбирайте Intel.</AccordionContent></AccordionItem></Accordion>
    {error&&<div className="release-warning" role="status"><span>{stale?'Не удалось обновить версию. Показан сохранённый релиз.':'Не удалось получить последний релиз. Сборки доступны на GitHub.'}</span><Button variant="ghost" size="icon" onClick={refresh} disabled={loading} aria-label="Повторить загрузку релиза"><RefreshCw className={`size-4 ${loading?'animate-spin':''}`}/></Button></div>}
    {loading&&!release?<Button disabled className="download-action"><LoaderCircle className="size-4 animate-spin"/>Проверяем релиз…</Button>:asset?<Button asChild className="download-action"><a href={asset.browser_download_url}><ArrowDown className="size-4"/>Скачать Mafus <span className="download-size">{Math.round(asset.size/1048576)} МБ</span></a></Button>:<Button asChild className="download-action"><a href={release?.html_url??RELEASES} target="_blank" rel="noopener noreferrer">Открыть сборки на GitHub<ArrowUpRight className="size-4"/></a></Button>}
    <div className="download-meta"><span>ZIP · Распакуйте и перенесите в «Программы»</span>{checksum&&<Button variant="ghost" size="sm" onClick={copyChecksum} className="checksum-button">{copied?<Check className="size-3.5"/>:<Copy className="size-3.5"/>}SHA-256</Button>}</div>
    <p className="dialog-note">Экспериментальный релиз с локальной подписью, без notarization. <a href="https://github.com/notnotshuts/Mafus/blob/main/docs/USAGE.ru.md" target="_blank" rel="noopener noreferrer">Инструкция запуска <ExternalLink className="size-3"/></a></p>
  </DialogContent></Dialog>;
}
