import type {Metadata} from 'next';
import {Providers} from '@/components/providers';
import {assetPath} from '@/lib/releases';
import './globals.css';
export const metadata:Metadata={
  metadataBase:new URL('https://notnotshuts.github.io'),
  title:'Mafus — загрузочный USB. Всё просто.',
  description:'Создавайте загрузочные USB Windows, Linux и FreeDOS прямо на Mac. Нативное приложение для Apple Silicon и Intel. Бесплатно и с открытым кодом.',
  alternates:{canonical:'/Mafus/'},
  icons:{icon:assetPath('mafus-logo.svg')},
  openGraph:{title:'Mafus. Новая система начинается здесь.',description:'Windows, Linux и FreeDOS. Ваш USB. Ваш Mac.',url:'https://notnotshuts.github.io/Mafus/',locale:'ru_RU',type:'website'},
};
export default function RootLayout({children}:{children:React.ReactNode}){
  return <html lang="ru" suppressHydrationWarning><body><Providers>{children}</Providers></body></html>;
}
