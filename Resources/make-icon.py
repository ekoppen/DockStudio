import math
def squircle(cx,cy,r,n=5,steps=360):
    pts=[]
    for i in range(steps):
        t=2*math.pi*i/steps
        c,s=math.cos(t),math.sin(t)
        x=cx+r*math.copysign(abs(c)**(2/n),c)
        y=cy+r*math.copysign(abs(s)**(2/n),s)
        pts.append(f"{x:.1f},{y:.1f}")
    return "M"+" L".join(pts)+"Z"
body=squircle(512,512,412)
tiles=[(221,72,'#2dd4bf','#0ea5a4'),(315,100,'#fbbf24','#f97316'),(437,150,'#ff6fb5','#c026d3'),(609,100,'#60a5fa','#4f46e5'),(731,72,'#a3e635','#16a34a')]
bottom=690
t=""
for x,s,a,b in tiles:
    y=bottom-s; r=s*0.23
    gid=f"g{x}"
    t+=f'''<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>
<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="url(#{gid})"/>
<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="url(#gloss)"/>
<rect x="{x+0.5}" y="{y+0.5}" width="{s-1}" height="{s-1}" rx="{r}" fill="none" stroke="#fff" stroke-opacity=".35"/>
'''
# sparkle on big tile
cx,cy=512,690-75
def star(cx,cy,R,r):
    p=[]
    for i in range(8):
        a=math.pi/4*i-math.pi/2
        rad=R if i%2==0 else r
        p.append(f"{cx+rad*math.cos(a):.1f},{cy+rad*math.sin(a):.1f}")
    return "M"+" L".join(p)+"Z"
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="#2a1d6e"/><stop offset=".55" stop-color="#5a2bc4"/><stop offset="1" stop-color="#c0388f"/></linearGradient>
<radialGradient id="glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#ff7cc4" stop-opacity=".85"/><stop offset="1" stop-color="#ff7cc4" stop-opacity="0"/></radialGradient>
<radialGradient id="top" cx=".3" cy="0" r="1"><stop offset="0" stop-color="#fff" stop-opacity=".30"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/></radialGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".45"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="pill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".32"/><stop offset="1" stop-color="#fff" stop-opacity=".12"/></linearGradient>
<linearGradient id="pillStroke" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".7"/><stop offset="1" stop-color="#fff" stop-opacity=".15"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="14"/></filter>
<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter>
<filter id="ds" x="-20%" y="-20%" width="150%" height="150%"><feDropShadow dx="0" dy="6" stdDeviation="7" flood-color="#000" flood-opacity=".45"/></filter>
<clipPath id="clip"><path d="{body}"/></clipPath>
</defs>
<g filter="url(#sh)" opacity=".5" transform="translate(0,22)"><path d="{body}" fill="#0a0420"/></g>
<path d="{body}" fill="url(#bg)"/>
<g clip-path="url(#clip)">
 <rect width="1024" height="1024" fill="url(#top)"/>
 <ellipse cx="512" cy="640" rx="330" ry="200" fill="url(#glow)" filter="url(#soft)"/>
 <circle cx="780" cy="250" r="150" fill="#7c4dff" opacity=".35" filter="url(#soft)"/>
</g>
<g transform="translate(512,512) scale(1.12) translate(-512,-548)">
<rect x="170" y="560" width="684" height="150" rx="64" fill="#0a0420" opacity=".35" filter="url(#sh)" transform="translate(0,14)"/>
<rect x="170" y="560" width="684" height="150" rx="64" fill="url(#pill)"/>
<rect x="171" y="561" width="682" height="148" rx="63" fill="none" stroke="url(#pillStroke)" stroke-width="2.5"/>
<g filter="url(#ds)">{t}</g>
<path d="{star(512,615,44,11)}" fill="#fff" opacity=".95"/>
<path d="{star(560,578,16,4)}" fill="#fff" opacity=".8"/>
<g transform="translate(590,415) rotate(-8)" filter="url(#ds)">
 <path d="M0,0 L0,118 L30,92 L50,138 L72,128 L52,84 L92,84 Z" fill="#fff" stroke="#1a1040" stroke-width="7" stroke-linejoin="round"/>
</g>
</g>
<path d="{body}" fill="none" stroke="#fff" stroke-opacity=".28" stroke-width="3"/>
</svg>'''
open('icon.svg','w').write(svg)
