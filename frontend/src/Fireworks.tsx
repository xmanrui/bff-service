import { useEffect, useRef } from 'react'

interface Particle {
  x: number
  y: number
  vx: number
  vy: number
  alpha: number
  color: string
  decay: number
  size: number
}

interface Rocket {
  x: number
  y: number
  vy: number
  targetY: number
  color: string
  trail: { x: number; y: number; alpha: number }[]
}

const COLORS = [
  '#FFD700', '#FFA500', '#FF6347', '#FF4500',
  '#DC143C', '#FF1493', '#FFB6C1', '#FFDAB9',
  '#FF8C00', '#E53935', '#D32F2F', '#FFEB3B',
]

function randomColor() {
  return COLORS[Math.floor(Math.random() * COLORS.length)]
}

export default function Fireworks() {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current!
    const ctx = canvas.getContext('2d')!
    let animId: number
    const particles: Particle[] = []
    const rockets: Rocket[] = []
    let lastLaunch = 0

    function resize() {
      canvas.width = window.innerWidth
      canvas.height = window.innerHeight
    }
    resize()
    window.addEventListener('resize', resize)

    function explode(x: number, y: number, color: string) {
      const count = 60 + Math.random() * 40
      for (let i = 0; i < count; i++) {
        const angle = (Math.PI * 2 * i) / count
        const speed = 1.5 + Math.random() * 3.5
        particles.push({
          x,
          y,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          alpha: 1,
          color: Math.random() > 0.3 ? color : randomColor(),
          decay: 0.012 + Math.random() * 0.01,
          size: 1.5 + Math.random() * 1.5,
        })
      }
    }

    function loop(time: number) {
      ctx.globalCompositeOperation = 'source-over'
      ctx.fillStyle = 'rgba(0,0,0,0.15)'
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.globalCompositeOperation = 'lighter'

      // Launch rockets
      if (time - lastLaunch > 400 + Math.random() * 600) {
        lastLaunch = time
        const x = canvas.width * 0.15 + Math.random() * canvas.width * 0.7
        rockets.push({
          x,
          y: canvas.height,
          vy: -(8 + Math.random() * 4),
          targetY: canvas.height * 0.1 + Math.random() * canvas.height * 0.35,
          color: randomColor(),
          trail: [],
        })
      }

      // Update rockets
      for (let i = rockets.length - 1; i >= 0; i--) {
        const r = rockets[i]
        r.trail.push({ x: r.x, y: r.y, alpha: 1 })
        r.y += r.vy
        r.vy *= 0.98

        // Draw trail
        for (let j = r.trail.length - 1; j >= 0; j--) {
          const t = r.trail[j]
          t.alpha -= 0.04
          if (t.alpha <= 0) {
            r.trail.splice(j, 1)
            continue
          }
          ctx.beginPath()
          ctx.arc(t.x, t.y, 1.5, 0, Math.PI * 2)
          ctx.fillStyle = `rgba(255,200,100,${t.alpha})`
          ctx.fill()
        }

        // Draw rocket head
        ctx.beginPath()
        ctx.arc(r.x, r.y, 2.5, 0, Math.PI * 2)
        ctx.fillStyle = '#fff'
        ctx.fill()

        if (r.y <= r.targetY) {
          explode(r.x, r.y, r.color)
          rockets.splice(i, 1)
        }
      }

      // Update particles
      for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i]
        p.x += p.vx
        p.y += p.vy
        p.vy += 0.04
        p.vx *= 0.99
        p.alpha -= p.decay

        if (p.alpha <= 0) {
          particles.splice(i, 1)
          continue
        }

        ctx.beginPath()
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2)
        ctx.fillStyle = p.color
        ctx.globalAlpha = p.alpha
        ctx.fill()
        ctx.globalAlpha = 1
      }

      animId = requestAnimationFrame(loop)
    }

    animId = requestAnimationFrame(loop)

    return () => {
      cancelAnimationFrame(animId)
      window.removeEventListener('resize', resize)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        width: '100%',
        height: '100%',
        pointerEvents: 'none',
        zIndex: 0,
      }}
    />
  )
}
