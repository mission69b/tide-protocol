"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"  // ← now from shadcn

export function ThemeToggle() {
  const [darkMode, setDarkMode] = useState(false)

  useEffect(() => {
    const saved = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const isDark = saved ? saved === "dark" : prefersDark
    setDarkMode(isDark)
    document.documentElement.classList.toggle("dark", isDark)
  }, [])

  const toggle = () => {
    const newMode = !darkMode
    setDarkMode(newMode)
    document.documentElement.classList.toggle("dark", newMode)
    localStorage.setItem("theme", newMode ? "dark" : "light")
  }

  return (
    <Button variant="outline" size="icon" onClick={toggle}>
      {darkMode ? "☀️" : "🌙"}
    </Button>
  )
}
