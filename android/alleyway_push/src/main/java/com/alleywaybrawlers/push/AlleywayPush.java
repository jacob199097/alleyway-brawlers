package com.alleywaybrawlers.push;

import android.app.Activity;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;

import androidx.annotation.NonNull;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Phone notifications for the game (godot/scripts/push.gd): the notification channels, and this phone's
 * Firebase Cloud Messaging token for the server (backend/utils/push.js). Firebase starts itself from the
 * project's IDs (res/values/firebase.xml, made from google-services.json by tools/build_android.mjs), so
 * its own service can show a notification even when the game isn't running.
 */
public class AlleywayPush extends GodotPlugin {

    public AlleywayPush(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "AlleywayPush";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("token", String.class));
        signals.add(new SignalInfo("failed", String.class));
        return signals;
    }

    /** A notification channel (Android 8 and newer): what the phone's settings list, each on or off. */
    @UsedByGodot
    public void createChannel(String id, String name, String description, int importance) {
        Activity activity = getActivity();
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationChannel channel = new NotificationChannel(id, name, importance);
        channel.setDescription(description);
        NotificationManager manager = activity.getSystemService(NotificationManager.class);
        if (manager != null) manager.createNotificationChannel(channel);
    }

    /** This phone's token: the "token" signal, or "failed" with why. */
    @UsedByGodot
    public void requestToken() {
        Activity activity = getActivity();
        try {
            if (activity != null && FirebaseApp.getApps(activity).isEmpty()) FirebaseApp.initializeApp(activity);
            FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
                if (task.isSuccessful() && task.getResult() != null) {
                    String token = task.getResult();
                    runOnRenderThread(() -> emitSignal("token", token));
                } else {
                    String why = task.getException() != null ? String.valueOf(task.getException().getMessage()) : "no token";
                    runOnRenderThread(() -> emitSignal("failed", why));
                }
            });
        } catch (Exception e) {
            String why = String.valueOf(e.getMessage());
            runOnRenderThread(() -> emitSignal("failed", why));
        }
    }
}
