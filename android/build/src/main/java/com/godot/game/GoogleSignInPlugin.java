package com.godot.game;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import com.google.android.gms.auth.api.signin.GoogleSignIn;
import com.google.android.gms.auth.api.signin.GoogleSignInAccount;
import com.google.android.gms.auth.api.signin.GoogleSignInClient;
import com.google.android.gms.auth.api.signin.GoogleSignInOptions;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.tasks.Task;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;

/**
 * Native Android plugin to prompt the Google account selector
 * and return the Google ID Token to Godot.
 */
public class GoogleSignInPlugin extends GodotPlugin {
    private static final String TAG = "GoogleSignInPlugin";
    private static final int RC_SIGN_IN = 9001;

    public GoogleSignInPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GoogleSignIn";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("sign_in_completed", String.class));
        signals.add(new SignalInfo("sign_in_failed", String.class));
        return signals;
    }

    private GoogleSignInClient getClient(Activity activity, String webClientId) {
        GoogleSignInOptions.Builder builder = new GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN);
        if (webClientId != null && !webClientId.isEmpty()) {
            builder.requestIdToken(webClientId).requestEmail();
        }
        return GoogleSignIn.getClient(activity, builder.build());
    }

    @UsedByGodot
    public void signIn(String webClientId) {
        Log.i(TAG, "signIn called with webClientId: " + webClientId);
        switchAccount(webClientId);
    }

    @UsedByGodot
    public void signOut() {
        Log.i(TAG, "signOut called");
        Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            GoogleSignInOptions gso = new GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN).build();
            GoogleSignInClient client = GoogleSignIn.getClient(activity, gso);
            client.signOut();
        });
    }

    @UsedByGodot
    public void switchAccount(String webClientId) {
        Log.i(TAG, "switchAccount called with webClientId: " + webClientId);
        Activity activity = getActivity();
        if (activity == null) {
            emitSignal("sign_in_failed", "Activity is null");
            return;
        }

        activity.runOnUiThread(() -> {
            GoogleSignInClient client = getClient(activity, webClientId);
            client.signOut().addOnCompleteListener(activity, signOutTask -> {
                Log.i(TAG, "signOut completed, success=" + signOutTask.isSuccessful() + ", launching Intent");
                Intent signInIntent = client.getSignInIntent();
                activity.startActivityForResult(signInIntent, RC_SIGN_IN);
            });
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        Log.i(TAG, "onMainActivityResult: requestCode=" + requestCode + ", resultCode=" + resultCode);
        if (requestCode == RC_SIGN_IN) {
            Task<GoogleSignInAccount> task = GoogleSignIn.getSignedInAccountFromIntent(data);
            try {
                GoogleSignInAccount account = task.getResult(ApiException.class);
                if (account != null) {
                    String idToken = account.getIdToken();
                    Log.i(TAG, "signIn success: account=" + account.getEmail() + ", hasToken=" + (idToken != null && !idToken.isEmpty()));
                    emitSignal("sign_in_completed", idToken != null ? idToken : "");
                } else {
                    Log.w(TAG, "Google account was null");
                    emitSignal("sign_in_failed", "Google account was null");
                }
            } catch (ApiException e) {
                Log.w(TAG, "signInResult:failed code=" + e.getStatusCode() + " - " + e.getMessage());
                emitSignal("sign_in_failed", "Status code: " + e.getStatusCode() + " - " + e.getMessage());
            }
        }
    }
}
