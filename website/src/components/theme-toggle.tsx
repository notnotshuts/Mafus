'use client';
import {useTheme} from 'next-themes';
import {Monitor,Moon,Sun,Check} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {DropdownMenu,DropdownMenuContent,DropdownMenuItem,DropdownMenuTrigger} from '@/components/ui/dropdown-menu';
export function ThemeToggle(){
  const {theme,setTheme}=useTheme();
  return <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="theme-toggle" aria-label="Выбрать тему оформления"><Sun className="size-[18px] rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0"/><Moon className="absolute size-[18px] rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100"/></Button></DropdownMenuTrigger>
    <DropdownMenuContent align="end" className="w-44">{[{value:'light',name:'Светлая',Icon:Sun},{value:'dark',name:'Тёмная',Icon:Moon},{value:'system',name:'Как в системе',Icon:Monitor}].map(({value,name,Icon})=><DropdownMenuItem key={value} onSelect={()=>setTheme(value)}><Icon className="size-4"/>{name}{theme===value&&<Check className="ml-auto size-4"/>}</DropdownMenuItem>)}</DropdownMenuContent>
  </DropdownMenu>;
}
