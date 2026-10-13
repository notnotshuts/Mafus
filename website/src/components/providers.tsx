'use client';
import {ThemeProvider} from 'next-themes';
import {LazyMotion,domAnimation} from 'motion/react';
import {Toaster} from 'sonner';
import {ReleaseProvider} from './release-provider';
export function Providers({children}:{children:React.ReactNode}){
  return <ThemeProvider attribute="class" defaultTheme="system" enableSystem storageKey="mafus-theme" disableTransitionOnChange>
    <LazyMotion features={domAnimation} strict><ReleaseProvider>{children}</ReleaseProvider></LazyMotion>
    <Toaster position="bottom-center" richColors />
  </ThemeProvider>;
}
