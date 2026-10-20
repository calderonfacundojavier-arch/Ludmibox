/* Service worker mínimo: siempre prueba primero la red (así nunca queda una versión vieja) y usa la copia guardada solo si no hay conexión. No toca pedidos a Supabase. */
const V="v2";
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("fetch",e=>{
  const r=e.request;
  if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
  e.respondWith(fetch(r).then(res=>{
    if(res.ok){const c=res.clone();caches.open(V).then(x=>x.put(r,c)).catch(()=>{})}
    return res;
  }).catch(()=>caches.match(r).then(m=>m||caches.match("/ludmi"))));
});

/* Avisos push: llegan aunque la app esté cerrada */
self.addEventListener("push",e=>{
  let d={};try{d=e.data?e.data.json():{}}catch{}
  e.waitUntil((async()=>{
    const cs=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    if(cs.some(c=>c.visibilityState==="visible"&&c.focused))return; /* ya lo está viendo: avisa la propia página */
    await self.registration.showNotification(d.title||"Mensaje nuevo",{body:d.body||"",icon:"/icon-192.png",badge:"/icon-192.png",tag:d.tag||"chat",renotify:true,data:{url:d.url||"/",vid:d.vid||null}});
  })());
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  const url=(e.notification.data&&e.notification.data.url)||"/";
  e.waitUntil((async()=>{
    const cs=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const c of cs){if(new URL(c.url).pathname.replace(/\/$/,"")===url.replace(/\/$/,"")){await c.focus();return}}
    await self.clients.openWindow(url);
  })());
});
