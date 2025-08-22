# Communities App

`Communities App` es una aplicación desarrollada en **Flutter** que permite a los usuarios gestionar y participar en diversas comunidades. Esta aplicación incluye funcionalidades como la gestión de eventos, la sincronización de datos entre la API y el almacenamiento local, y la implementación de notificaciones.

## Características

- **Gestión de eventos**: Permite a los usuarios ver eventos, marcarlos como leídos y sincronizar el estado de los eventos con un servidor remoto.
- **Sincronización con almacenamiento local**: Utiliza `SharedPreferences` para almacenar eventos y su estado de lectura en el dispositivo local.
- **Notificaciones**: Implementación de notificaciones pull para recibir actualizaciones periódicas en segundo plano en Android e iOS.
- **Compatibilidad con Android e iOS**: La aplicación está diseñada para ser compatible tanto con Android como con iOS.
- **Interfaz de usuario**: La interfaz de la aplicación está desarrollada con Flutter, aprovechando la capacidad de personalización de la UI en ambas plataformas.

## Configuración del entorno de desarrollo

### Requisitos previos

- **Flutter** 3.0.0 o superior
- **Dart** 2.17 o superior
- **Android SDK** y **Xcode** (para la compilación en iOS)
- **Kotlin** para Android