import type { Metadata } from "next"
import "./globals.css"  // Make sure this is imported
import { ThemeToggle } from "@/components/ThemeToggle"  // Adjust alias if needed (@/*)

export const metadata: Metadata = {
  title: "Tide Protocol",
  description: "...",
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <header className="p-4 flex justify-end">
          <ThemeToggle />
        </header>
        {children}
      </body>
    </html>
  )
}
