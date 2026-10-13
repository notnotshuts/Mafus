'use client';
import {useEffect,useRef,useState,type ReactNode} from 'react';
import {m,useInView,useReducedMotion} from 'motion/react';
export function Reveal({children,className}:{children:ReactNode;className?:string}){
  const ref=useRef<HTMLDivElement>(null);const visible=useInView(ref,{once:true,amount:0.12});
  const reduced=useReducedMotion();const [ready,setReady]=useState(false);
  useEffect(()=>setReady(true),[]);
  return <m.div ref={ref} className={className} initial={false} animate={!ready||visible||reduced?{opacity:1,y:0}:{opacity:0,y:18}} transition={{duration:0.28,ease:[0.2,0.65,0.3,1]}}>{children}</m.div>;
}
