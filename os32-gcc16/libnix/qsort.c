#include <stdlib.h>

/* libnix's qsort, fixed so that it ends and stays inside the array for every
 * comparison function. Public domain, as libnix.
 *
 * The old one took the middle element as the pivot and left it in the array,
 * where the scan from the left reached it and stopped only because
 * compar(pivot, pivot) returned 0. A comparison function that never returns 0
 * (libwebp's Huffman-tree and palette sorts: "return (a < b) ? -1 : 1;") made
 * that scan run past the pivot and past the end of the part being sorted. When
 * the pivot was the part's last element in sort order (any two elements in the
 * wrong order, for one), both scans then met at the last element, the part
 * split into all of it and nothing, and the loop below went round for ever.
 *
 * Here the pivot is moved to the front first. Both scans are bounded, compar
 * never gets the pivot as both arguments, and the pivot goes to its own place
 * between the two parts after each pass, so every pass takes at least one
 * element out and the sort always ends.
 *
 * As before, it recurses on the smaller part and goes round again for the
 * larger one, so the stack is at most log2(nmemb) calls deep.
 */

static void swap(char *x,char *y,size_t size)
{ do
  { char tmp=*x;
    *x++=*y;
    *y++=tmp;
  }while(--size);
}

void qsort
(void *base,size_t nmemb,size_t size,int (*compar)(const void *,const void *))
{ char *base2=(char *)base;
  size_t a,b;
  if(size==0)
    return;
  while(nmemb>1)
  { a=(nmemb-1)/2; /* Middle element is the pivot... */
    if(a!=0)
      swap(base2,&base2[size*a],size); /* ...kept at the front */
    a=1;
    b=nmemb-1;
    for(;;)
    { while(a<=b&&(*compar)(base2,&base2[size*a])>0)
        a++; /* Look for one >= pivot */
      while(a<=b&&(*compar)(base2,&base2[size*b])<0)
        b--; /* Look for one <= pivot */
      if(a>=b)
        break; /* We found no pair */
      swap(&base2[size*a],&base2[size*b],size);
      a++; /* These two are already sorted */
      b--;
    } /* 1..a-1 are <= pivot, a..nmemb-1 are >= pivot */
    a--; /* The pivot's own place */
    if(a!=0)
      swap(base2,&base2[size*a],size);
    b=nmemb-1-a; /* Elements right of the pivot */
    if(a<b) /* do recursion on smaller interval and iteration on larger one */
    { qsort(base2,a,size,compar);
      base2=&base2[size*(a+1)];
      nmemb=b; }
    else
    { qsort(&base2[size*(a+1)],b,size,compar);
      nmemb=a; }
  }
}
