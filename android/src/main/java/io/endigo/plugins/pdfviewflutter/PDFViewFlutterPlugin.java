package io.endigo.plugins.pdfviewflutter;

import android.app.Activity;
import android.app.Dialog;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public class PDFViewFlutterPlugin implements MethodCallHandler {
    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        registrar
                .platformViewRegistry()
                .registerViewFactory(
                        "plugins.endigo.io/pdfview", new PDFViewFactory(registrar.messenger()));


        final MethodChannel channel = new MethodChannel(registrar.messenger(), "Pdf_To_Image");
        channel.setMethodCallHandler(new PDFViewFlutterPlugin(registrar.activity(), channel));
    }


    /**
     * Plugin registration.
     */
    Activity context;
    MethodChannel methodChannel;

    public PDFViewFlutterPlugin(Activity activity, MethodChannel methodChannel) {
        this.context = activity;
        this.methodChannel = methodChannel;
        this.methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        if (call.method.equals("PdfToImage")) {
            new PdfToImage(context, call, result);
        } else {
            result.notImplemented();
        }
    }

}
