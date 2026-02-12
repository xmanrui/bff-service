import { useState } from 'react'
import Fireworks from './Fireworks'

const jokes = [
  "为什么程序员总是分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。",
  "Java 和 JavaScript 有什么关系？就像雷锋和雷峰塔的关系。",
  "为什么程序员不喜欢户外？因为有太多 bug。",
  "一个 SQL 语句走进酒吧，看到两张 table，问：Can I JOIN you?",
  "为什么前端程序员吃饭不用筷子？因为他们只会用 div。",
  "程序员最讨厌的电影？《无间道》——因为死循环。",
  "为什么 C 语言程序员戴眼镜？因为他们看不到 C#。",
  "HTTP 是什么意思？How To Teach People（如何教人）。",
  "为什么程序员总是把圣诞节和万圣节搞混？因为他们觉得 25 Dec == 31 Oct。",
  "老板：这个 bug 什么时候能修好？程序员：等它变成 feature 就好了。",
  "为什么北极熊不吃企鹅？因为它打不开包装。",
  "我跟我的代码说了一个笑话，它没反应——大概是没有 sense of humor，只有 syntax error。",
]

const links = [
  { label: '📖 API Docs', href: '/docs' },
  { label: '📘 ReDoc', href: '/redoc' },
  { label: '❤️ Health', href: '/health' },
  { label: '👥 Users', href: '/api/v1/users' },
  { label: '📦 Items', href: '/api/v1/items' },
]

function randomJoke(current: number): number {
  let next: number
  do {
    next = Math.floor(Math.random() * jokes.length)
  } while (next === current && jokes.length > 1)
  return next
}

export default function App() {
  const [jokeIdx, setJokeIdx] = useState(() => Math.floor(Math.random() * jokes.length))

  return (
    <div
      className="relative min-h-screen flex items-center justify-center"
      style={{ background: 'linear-gradient(135deg, #1b5e20, #2e7d32, #66bb6a)' }}
    >
      <Fireworks />

      <div className="relative z-10 text-center text-white px-4 max-w-2xl mx-auto">
        {/* Logo */}
        <div className="text-7xl mb-4 drop-shadow-lg">🧧</div>

        {/* Title */}
        <h1 className="text-5xl font-bold mb-3 drop-shadow-md">Hello world!</h1>

        {/* Blessing */}
        <p className="text-2xl mb-2 drop-shadow">🎆 新春快乐，万事如意！🎆</p>

        {/* Subtitle */}
        <p className="text-lg opacity-80 mb-8">Built with FastAPI · Ready to serve</p>

        {/* Joke */}
        <div
          onClick={() => setJokeIdx(randomJoke(jokeIdx))}
          className="bg-white/15 backdrop-blur-sm rounded-xl px-6 py-4 mb-8 cursor-pointer
                     hover:bg-white/25 transition-colors select-none"
        >
          <p className="text-base leading-relaxed">💡 {jokes[jokeIdx]}</p>
          <p className="text-xs opacity-60 mt-2">点击换一个冷笑话 👆</p>
        </div>

        {/* Links */}
        <div className="flex flex-wrap justify-center gap-3 mb-8">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="bg-white/20 hover:bg-white/35 backdrop-blur-sm rounded-lg px-4 py-2
                         text-sm font-medium transition-colors"
            >
              {l.label}
            </a>
          ))}
        </div>

        {/* Status */}
        <p className="text-sm opacity-75">✅ Service is running</p>
      </div>
    </div>
  )
}
