'use client';
import {useState} from 'react';
import {AnimatePresence,m,useReducedMotion} from 'motion/react';
import {ArrowDownToLine,Check,Disc3,HardDrive,SlidersHorizontal,Sparkles} from 'lucide-react';
import {Tabs,TabsList,TabsTrigger} from '@/components/ui/tabs';
import {assetPath} from '@/lib/releases';
const modes={
  windows:{name:'Windows',file:'Windows11_x64.iso',detail:'Windows 11 · установочный ISO',note:'UEFI · NTFS · большие образы без разбиения',size:'6,1 ГБ'},
  linux:{name:'Linux',file:'linuxmint-cinnamon.iso',detail:'Linux Mint · Live ISO',note:'Linux Live · сохранять файлы и настройки',size:'2,9 ГБ'},
  dos:{name:'FreeDOS',file:'FD14-LiteUSB.zip',detail:'FreeDOS 1.4 · официальный образ',note:'DOS · загрузка через BIOS / CSM',size:'24 МБ'},
};
type Mode=keyof typeof modes;
export function AppPreview(){
  const [mode,setMode]=useState<Mode>('windows');const reduced=useReducedMotion();const item=modes[mode];
  return <div className="preview-composition"><div className="preview-halo" aria-hidden="true"/><div className="mafus-window" aria-describedby="preview-caption">
    <div className="window-chrome"><div className="traffic-lights" aria-hidden="true"><i/><i/><i/></div><span>Mafus</span><span className="window-shortcut" aria-hidden="true">⌘</span></div>
    <div className="window-main"><div className="preview-heading"><img src={assetPath('mafus-logo.svg')} width="58" height="58" alt=""/><div><h2>mafus</h2><p>Ваш загрузочный USB</p></div></div>
    <Tabs value={mode} onValueChange={value=>setMode(value as Mode)} className="preview-tabs"><TabsList aria-label="Пример системы"><TabsTrigger value="windows">Windows</TabsTrigger><TabsTrigger value="linux">Linux</TabsTrigger><TabsTrigger value="dos">FreeDOS</TabsTrigger></TabsList></Tabs>
    <AnimatePresence mode="wait" initial={false}><m.div key={mode} initial={reduced?false:{opacity:0,y:5}} animate={{opacity:1,y:0}} exit={{opacity:0,y:-5}} transition={{duration:0.15}} className="preview-panel" role="tabpanel" aria-label={`Пример: ${item.name}`}>
      <p className="preview-label">Образ системы</p><div className="preview-input"><Disc3 className="preview-input-icon" strokeWidth={1.5}/><div><strong>{item.file}</strong><span>{item.size} · {item.detail}</span></div><span className="preview-file-action">Изменить</span></div>
      <p className="preview-label">USB-накопитель</p><div className="preview-input"><HardDrive className="preview-input-icon" strokeWidth={1.5}/><div><strong>Моя флешка</strong><span>64 ГБ · внешний USB</span></div><span className="preview-ready"><Check className="size-13"/><span>Готов</span></span></div>
      <div className="preview-mode"><Sparkles className="size-3.5"/><span>{item.note}</span><SlidersHorizontal className="size-4 ml-auto"/></div>
    </m.div></AnimatePresence>
    <div className="preview-start"><ArrowDownToLine className="size-4"/>Создать загрузочный USB</div><p className="preview-warning">Данные на выбранном USB будут стёрты</p></div>
  </div><p className="preview-caption" id="preview-caption">Иллюстрация интерфейса. Переключайте системы, чтобы посмотреть режимы.</p></div>;
}
