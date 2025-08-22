import UIKit
import Flutter
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let bgTaskId = "com.wflw.social.fetch"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    // Permisos de notificación
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error { print("Notif auth error:", error) }
      else { print("Notif granted:", granted) }
    }
    // FlutterAppDelegate ya conforma al delegate, solo lo asignamos
    center.delegate = self

    // Registrar BGTask
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { task in
        self.handleAppRefresh(task: task as! BGAppRefreshTask)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Presentación de notificaciones en foreground (con override y availability)
  override public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  // Programación BGTask
  @available(iOS 13.0, *)
  func scheduleAppRefresh() {
    let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
    req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do { try BGTaskScheduler.shared.submit(req) }
    catch { print("BGTask submit error:", error) }
  }

  // Ejecución BGTask
  @available(iOS 13.0, *)
  func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleAppRefresh()
    task.expirationHandler = { /* cancela trabajo si hace falta */ }

    // TODO: aquí tu “pull” real. Demo: dispara una local
    let content = UNMutableNotificationContent()
    content.title = "WeFlow Social"
    content.body = "Tienes nuevas actualizaciones"
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger),
      withCompletionHandler: nil
    )

    task.setTaskCompleted(success: true)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    if #available(iOS 13.0, *) { scheduleAppRefresh() }
    super.applicationDidEnterBackground(application)
  }
}
