package io.endigo.plugins.pdfviewflutter;

import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.ParcelFileDescriptor;

import com.shockwave.pdfium.PdfDocument;
import com.shockwave.pdfium.PdfPasswordException;
import com.shockwave.pdfium.PdfiumCore;

import java.io.File;
import java.io.FileOutputStream;
import java.util.HashMap;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;

public class PdfThumbNail {
    MethodCall call;
    public static MethodResultWrapper result;
    Context context;

    PdfThumbNail(Context context, MethodCall call, Result result) {
        this.context = context;
        this.call = call;
        this.result = new MethodResultWrapper(result);
        getThumbNail();
    }

    private void getThumbNail() {
        HashMap<String, Object> arguments = (HashMap<String, Object>) call.arguments;
        File pdfFile = new File((String) arguments.get("pdfFilePath"));
        String destThumbPath = (String) arguments.get("destThumbPath");

        ThumbNailParams params = new ThumbNailParams(context, pdfFile, destThumbPath, result);
        GetThumbNailInBackground myTask = new GetThumbNailInBackground();
        myTask.execute(params);
    }
}


class GetThumbNailInBackground extends AsyncTask<ThumbNailParams, Integer, String> {

    @Override
    protected String doInBackground(ThumbNailParams... params) {
        try {
            Bitmap bitmap = null;
            PdfiumCore pdfiumCore = new PdfiumCore(params[0].context);
            ParcelFileDescriptor fd = params[0].context.getContentResolver().openFileDescriptor(Uri.fromFile(params[0].pdfFile), "r");
            PdfDocument pdfDocument = pdfiumCore.newDocument(fd);
            pdfiumCore.openPage(pdfDocument, 0);
            int width = pdfiumCore.getPageWidthPoint(pdfDocument, 0);
            int height = pdfiumCore.getPageHeightPoint(pdfDocument, 0);
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            pdfiumCore.renderPageBitmap(pdfDocument, bitmap, 0, 0, 0, width, height, true);

            File dest = new File(params[0].destThumbPath);
            FileOutputStream out = null;
            out = new FileOutputStream(dest);
            bitmap.compress(Bitmap.CompressFormat.JPEG, 100, out);
            out.flush();
            out.close();
            pdfiumCore.closeDocument(pdfDocument);
            try {
                if (bitmap != null) {
                    bitmap.recycle();
                }
            } catch (Exception ignored) {

            }
            params[0].result.success(true);
        } catch (Exception e) {
            e.printStackTrace();
            params[0].result.error(" ", e.getMessage(), null);
        }
        return "";
    }

    // Always same signature
    @Override
    public void onPreExecute() {
    }

    @Override
    public void onPostExecute(String result) {
        super.onPostExecute(result);
    }

    @Override
    public void onProgressUpdate(Integer... parameters) {
        // Show in spinner, and access UI elements
    }
}

class ThumbNailParams {
    Context context;
    File pdfFile;
    String destThumbPath;
    MethodResultWrapper result;

    ThumbNailParams(Context context,
                    File pdfFile, String destThumbPath, MethodResultWrapper result) {
        this.context = context;
        this.pdfFile = pdfFile;
        this.destThumbPath = destThumbPath;
        this.result = result;
    }
}