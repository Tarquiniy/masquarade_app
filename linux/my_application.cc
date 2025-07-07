#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Добавьте этот обработчик для решения проблемы с клавиатурой
static gboolean on_key_event(GtkWidget* widget, GdkEventKey* event, gpointer user_data) {
  // Пропускаем события клавиши Alt
  if (event->keyval == GDK_KEY_Alt_L || event->keyval == GDK_KEY_Alt_R) {
    return TRUE; // Блокируем обработку
  }
  return FALSE; // Разрешаем обработку других клавиш
}

// В функции my_application_activate добавьте:
static void my_application_activate(GApplication* application) {
  // ... существующий код ...

  // Добавьте этот обработчик событий
  g_signal_connect(window, "key-press-event", G_CALLBACK(on_key_event), nullptr);
  g_signal_connect(window, "key-release-event", G_CALLBACK(on_key_event), nullptr);
}