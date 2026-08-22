import { TooltipProvider } from "@/components/ui/tooltip"
import { ThemeProvider } from "@/components/theme-provider"
import { MemoApp } from "@/features/memos/memo-app"

export default function App() {
  return (
    <ThemeProvider>
      <TooltipProvider>
        <MemoApp />
      </TooltipProvider>
    </ThemeProvider>
  )
}
