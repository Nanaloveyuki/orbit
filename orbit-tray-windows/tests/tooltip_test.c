#include <assert.h>
#include <stdio.h>
#include "../native_tray.c"

__declspec(noreturn) void moonbit_panic(void) { abort(); }

int main(void) {
  WCHAR tip[128] = L"previous tooltip content";
  moonbit_bytes_t text = moonbit_make_bytes(3, 0);
  memcpy(text, "new", 3);
  orbit_tray_fill_tip(tip, text);
  assert(wcscmp(tip, L"new") == 0);
  text[0] = 0xff;
  orbit_tray_fill_tip(tip, text);
  assert(tip[0] == 0);
  moonbit_decref(text);
  text = moonbit_make_bytes(127, 'x');
  orbit_tray_fill_tip(tip, text);
  assert(wcslen(tip) == 127 && tip[127] == 0);
  moonbit_decref(text);
  puts("tooltip: shortening, invalid UTF-8, and termination passed");
  return 0;
}
