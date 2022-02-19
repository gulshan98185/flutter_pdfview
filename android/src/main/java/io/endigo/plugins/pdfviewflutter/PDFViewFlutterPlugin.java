package io.endigo.plugins.pdfviewflutter;

import android.app.Activity;
import android.app.Dialog;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public class PDFViewFlutterPlugin implements MethodCallHandler, FlutterPlugin, ActivityAware {
    /**
     * Plugin registration.
     */
    Activity context;
    public static void registerWith(Registrar registrar) {
        registrar
                .platformViewRegistry()
                .registerViewFactory(
                        "plugins.endigo.io/pdfview", new PDFViewFactory(registrar.messenger()));


        final MethodChannel channel = new MethodChannel(registrar.messenger(), "Pdf_To_Image");

        PDFViewFlutterPlugin plugin = new PDFViewFlutterPlugin();
        plugin.context=registrar.activity();
        channel.setMethodCallHandler(plugin);
    }


    /**
     * Plugin registration.
     */


    public PDFViewFlutterPlugin() {

    }

//    @Override
//    public void onMethodCall(MethodCall call, Result result) {
//        if (call.method.equals("convert_pdf_to_image")) {
//            new PdfToImage(context, call, result);
//        }
//        if (call.method.equals("getPdfThumbNail")) {
//            new PdfThumbNail(context, call, result);
//        } else {
//            result.notImplemented();
//        }
//    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        if (call.method.equals("getPdfThumbNail")) {
            new PdfThumbNail(context, call, result);
        } else if (call.method.equals("PdfToImage")) {
            new PdfToImage(context, call, result);
        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        MethodChannel channel = new MethodChannel(binding.getBinaryMessenger(), "plugins.endigo.io/pdfview");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {

    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        context = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        context=null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        context = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        context=null;
    }
}
